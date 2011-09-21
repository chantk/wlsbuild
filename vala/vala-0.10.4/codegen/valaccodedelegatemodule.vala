/* valaccodedelegatemodule.vala
 *
 * Copyright (C) 2006-2010  Jürg Billeter
 * Copyright (C) 2006-2008  Raffaele Sandrini
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 *	Raffaele Sandrini <raffaele@sandrini.ch>
 */


/**
 * The link between an assignment and generated code.
 */
public class Vala.CCodeDelegateModule : CCodeArrayModule {
	public override void generate_delegate_declaration (Delegate d, CCodeDeclarationSpace decl_space) {
		if (decl_space.add_symbol_declaration (d, d.get_cname ())) {
			return;
		}

		string return_type_cname = d.return_type.get_cname ();

		if (d.return_type.is_real_non_null_struct_type ()) {
			// structs are returned via out parameter
			return_type_cname = "void";
		}

		if (return_type_cname == d.get_cname ()) {
			// recursive delegate
			return_type_cname = "GCallback";
		} else {
			generate_type_declaration (d.return_type, decl_space);
		}

		var cfundecl = new CCodeFunctionDeclarator (d.get_cname ());
		foreach (FormalParameter param in d.get_parameters ()) {
			generate_parameter (param, decl_space, new HashMap<int,CCodeFormalParameter> (), null);

			cfundecl.add_parameter ((CCodeFormalParameter) param.ccodenode);

			// handle array parameters
			if (!param.no_array_length && param.variable_type is ArrayType) {
				var array_type = (ArrayType) param.variable_type;
				
				var length_ctype = "int";
				if (param.direction != ParameterDirection.IN) {
					length_ctype = "int*";
				}
				
				for (int dim = 1; dim <= array_type.rank; dim++) {
					var cparam = new CCodeFormalParameter (get_parameter_array_length_cname (param, dim), length_ctype);
					cfundecl.add_parameter (cparam);
				}
			}
			// handle delegate parameters
			if (param.variable_type is DelegateType) {
				var deleg_type = (DelegateType) param.variable_type;
				var param_d = deleg_type.delegate_symbol;
				if (param_d.has_target) {
					var cparam = new CCodeFormalParameter (get_delegate_target_cname (get_variable_cname (param.name)), "void*");
					cfundecl.add_parameter (cparam);
				}
			}
		}
		if (!d.no_array_length && d.return_type is ArrayType) {
			// return array length if appropriate
			var array_type = (ArrayType) d.return_type;

			for (int dim = 1; dim <= array_type.rank; dim++) {
				var cparam = new CCodeFormalParameter (get_array_length_cname ("result", dim), "int*");
				cfundecl.add_parameter (cparam);
			}
		} else if (d.return_type is DelegateType) {
			// return delegate target if appropriate
			var deleg_type = (DelegateType) d.return_type;
			var result_d = deleg_type.delegate_symbol;
			if (result_d.has_target) {
				var cparam = new CCodeFormalParameter (get_delegate_target_cname ("result"), "void**");
				cfundecl.add_parameter (cparam);
			}
		} else if (d.return_type.is_real_non_null_struct_type ()) {
			var cparam = new CCodeFormalParameter ("result", "%s*".printf (d.return_type.get_cname ()));
			cfundecl.add_parameter (cparam);
		}
		if (d.has_target) {
			var cparam = new CCodeFormalParameter ("user_data", "void*");
			cfundecl.add_parameter (cparam);
		}
		if (d.get_error_types ().size > 0) {
			var cparam = new CCodeFormalParameter ("error", "GError**");
			cfundecl.add_parameter (cparam);
		}

		var ctypedef = new CCodeTypeDefinition (return_type_cname, cfundecl);
		ctypedef.deprecated = d.deprecated;

		decl_space.add_type_definition (ctypedef);
	}

	public override void visit_delegate (Delegate d) {
		d.accept_children (this);

		generate_delegate_declaration (d, source_declarations);

		if (!d.is_internal_symbol ()) {
			generate_delegate_declaration (d, header_declarations);
		}
		if (!d.is_private_symbol ()) {
			generate_delegate_declaration (d, internal_header_declarations);
		}
	}

	public override string get_delegate_target_cname (string delegate_cname) {
		return "%s_target".printf (delegate_cname);
	}

	public override CCodeExpression get_delegate_target_cexpression (Expression delegate_expr, out CCodeExpression delegate_target_destroy_notify) {
		bool is_out = false;
	
		delegate_target_destroy_notify = new CCodeConstant ("NULL");

		if (delegate_expr is UnaryExpression) {
			var unary_expr = (UnaryExpression) delegate_expr;
			if (unary_expr.operator == UnaryOperator.OUT || unary_expr.operator == UnaryOperator.REF) {
				delegate_expr = unary_expr.inner;
				is_out = true;
			}
		}

		bool expr_owned = delegate_expr.value_type.value_owned;

		if (delegate_expr is ReferenceTransferExpression) {
			var reftransfer_expr = (ReferenceTransferExpression) delegate_expr;
			delegate_expr = reftransfer_expr.inner;
		}
		
		if (delegate_expr is MethodCall) {
			var invocation_expr = (MethodCall) delegate_expr;
			if (invocation_expr.delegate_target_destroy_notify != null) {
				delegate_target_destroy_notify = invocation_expr.delegate_target_destroy_notify;
			}
			return invocation_expr.delegate_target;
		} else if (delegate_expr is LambdaExpression) {
			var lambda = (LambdaExpression) delegate_expr;
			var delegate_type = (DelegateType) delegate_expr.target_type;
			if (lambda.method.closure) {
				int block_id = get_block_id (current_closure_block);
				var delegate_target = get_variable_cexpression ("_data%d_".printf (block_id));
				if (expr_owned || delegate_type.is_called_once) {
					var ref_call = new CCodeFunctionCall (new CCodeIdentifier ("block%d_data_ref".printf (block_id)));
					ref_call.add_argument (delegate_target);
					delegate_target = ref_call;
					delegate_target_destroy_notify = new CCodeIdentifier ("block%d_data_unref".printf (block_id));
				}
				return delegate_target;
			} else if (get_this_type () != null || in_constructor) {
				CCodeExpression delegate_target = get_result_cexpression ("self");
				if (expr_owned || delegate_type.is_called_once) {
					if (get_this_type () != null) {
						var ref_call = new CCodeFunctionCall (get_dup_func_expression (get_this_type (), delegate_expr.source_reference));
						ref_call.add_argument (delegate_target);
						delegate_target = ref_call;
						delegate_target_destroy_notify = get_destroy_func_expression (get_this_type ());
					} else {
						// in constructor
						var ref_call = new CCodeFunctionCall (new CCodeIdentifier ("g_object_ref"));
						ref_call.add_argument (delegate_target);
						delegate_target = ref_call;
						delegate_target_destroy_notify = new CCodeIdentifier ("g_object_unref");
					}
				}
				return delegate_target;
			} else {
				return new CCodeConstant ("NULL");
			}
		} else if (delegate_expr.symbol_reference != null) {
			if (delegate_expr.symbol_reference is FormalParameter) {
				var param = (FormalParameter) delegate_expr.symbol_reference;
				if (param.captured) {
					// captured variables are stored on the heap
					var block = ((Method) param.parent_symbol).body;
					delegate_target_destroy_notify = new CCodeMemberAccess.pointer (get_variable_cexpression ("_data%d_".printf (get_block_id (block))), get_delegate_target_destroy_notify_cname (get_variable_cname (param.name)));
					return new CCodeMemberAccess.pointer (get_variable_cexpression ("_data%d_".printf (get_block_id (block))), get_delegate_target_cname (get_variable_cname (param.name)));
				} else if (current_method != null && current_method.coroutine) {
					delegate_target_destroy_notify = new CCodeMemberAccess.pointer (new CCodeIdentifier ("data"), get_delegate_target_destroy_notify_cname (get_variable_cname (param.name)));
					return new CCodeMemberAccess.pointer (new CCodeIdentifier ("data"), get_delegate_target_cname (get_variable_cname (param.name)));
				} else {
					CCodeExpression target_expr = new CCodeIdentifier (get_delegate_target_cname (get_variable_cname (param.name)));
					if (expr_owned) {
						delegate_target_destroy_notify = new CCodeIdentifier (get_delegate_target_destroy_notify_cname (get_variable_cname (param.name)));
					}
					if (param.direction != ParameterDirection.IN) {
						// accessing argument of out/ref param
						target_expr = new CCodeUnaryExpression (CCodeUnaryOperator.POINTER_INDIRECTION, target_expr);
						if (expr_owned) {
							delegate_target_destroy_notify = new CCodeUnaryExpression (CCodeUnaryOperator.POINTER_INDIRECTION, delegate_target_destroy_notify);
						}
					}
					if (is_out) {
						// passing delegate as out/ref
						if (expr_owned) {
							delegate_target_destroy_notify = new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, delegate_target_destroy_notify);
						}
						return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, target_expr);
					} else {
						return target_expr;
					}
				}
			} else if (delegate_expr.symbol_reference is LocalVariable) {
				var local = (LocalVariable) delegate_expr.symbol_reference;
				if (local.captured) {
					// captured variables are stored on the heap
					var block = (Block) local.parent_symbol;
					delegate_target_destroy_notify = new CCodeMemberAccess.pointer (get_variable_cexpression ("_data%d_".printf (get_block_id (block))), get_delegate_target_destroy_notify_cname (get_variable_cname (local.name)));
					return new CCodeMemberAccess.pointer (get_variable_cexpression ("_data%d_".printf (get_block_id (block))), get_delegate_target_cname (get_variable_cname (local.name)));
				} else if (current_method != null && current_method.coroutine) {
					delegate_target_destroy_notify = new CCodeMemberAccess.pointer (new CCodeIdentifier ("data"), get_delegate_target_destroy_notify_cname (get_variable_cname (local.name)));
					return new CCodeMemberAccess.pointer (new CCodeIdentifier ("data"), get_delegate_target_cname (get_variable_cname (local.name)));
				} else {
					var target_expr = new CCodeIdentifier (get_delegate_target_cname (get_variable_cname (local.name)));
					if (expr_owned) {
						delegate_target_destroy_notify = new CCodeIdentifier (get_delegate_target_destroy_notify_cname (get_variable_cname (local.name)));
					}
					if (is_out) {
						if (expr_owned) {
							delegate_target_destroy_notify = new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, delegate_target_destroy_notify);
						}
						return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, target_expr);
					} else {
						return target_expr;
					}
				}
			} else if (delegate_expr.symbol_reference is Field) {
				var field = (Field) delegate_expr.symbol_reference;
				string target_cname = get_delegate_target_cname (field.get_cname ());
				string target_destroy_notify_cname = get_delegate_target_destroy_notify_cname (field.get_cname ());

				var ma = (MemberAccess) delegate_expr;

				CCodeExpression target_expr = null;

				if (field.no_delegate_target) {
					return new CCodeConstant ("NULL");
				}

				if (field.binding == MemberBinding.INSTANCE) {
					var instance_expression_type = ma.inner.value_type;
					var instance_target_type = get_data_type_for_symbol ((TypeSymbol) field.parent_symbol);

					var pub_inst = (CCodeExpression) get_ccodenode (ma.inner);
					CCodeExpression typed_inst = transform_expression (pub_inst, instance_expression_type, instance_target_type);

					CCodeExpression inst;
					if (field.access == SymbolAccessibility.PRIVATE) {
						inst = new CCodeMemberAccess.pointer (typed_inst, "priv");
					} else {
						inst = typed_inst;
					}
					if (((TypeSymbol) field.parent_symbol).is_reference_type ()) {
						target_expr = new CCodeMemberAccess.pointer (inst, target_cname);
						if (expr_owned) {
							delegate_target_destroy_notify = new CCodeMemberAccess.pointer (inst, target_destroy_notify_cname);
						}
					} else {
						target_expr = new CCodeMemberAccess (inst, target_cname);
						if (expr_owned) {
							delegate_target_destroy_notify = new CCodeMemberAccess (inst, target_destroy_notify_cname);
						}
					}
				} else {
					target_expr = new CCodeIdentifier (target_cname);
					if (expr_owned) {
						delegate_target_destroy_notify = new CCodeIdentifier (target_destroy_notify_cname);
					}
				}

				if (is_out) {
					return new CCodeUnaryExpression (CCodeUnaryOperator.ADDRESS_OF, target_expr);
				} else {
					return target_expr;
				}
			} else if (delegate_expr.symbol_reference is Method) {
				var m = (Method) delegate_expr.symbol_reference;
				var ma = (MemberAccess) delegate_expr;
				if (m.binding == MemberBinding.STATIC) {
					return new CCodeConstant ("NULL");
				} else if (m.is_async_callback) {
					if (current_method.closure) {
						var block = ((Method) m.parent_symbol).body;
						return new CCodeMemberAccess.pointer (get_variable_cexpression ("_data%d_".printf (get_block_id (block))), "_async_data_");
					} else {
						return new CCodeIdentifier ("data");
					}
				} else {
					var delegate_target = (CCodeExpression) get_ccodenode (ma.inner);
					var delegate_type = delegate_expr.target_type as DelegateType;
					if ((expr_owned || (delegate_type != null && delegate_type.is_called_once)) && ma.inner.value_type.data_type != null && ma.inner.value_type.data_type.is_reference_counting ()) {
						var ref_call = new CCodeFunctionCall (get_dup_func_expression (ma.inner.value_type, delegate_expr.source_reference));
						ref_call.add_argument (delegate_target);
						delegate_target = ref_call;
						delegate_target_destroy_notify = get_destroy_func_expression (ma.inner.value_type);
					}
					return delegate_target;
				}
			} else if (delegate_expr.symbol_reference is Property) {
				return delegate_expr.delegate_target;
			}
		}

		return new CCodeConstant ("NULL");
	}

	public override string get_delegate_target_destroy_notify_cname (string delegate_cname) {
		return "%s_target_destroy_notify".printf (delegate_cname);
	}

	public override CCodeExpression get_implicit_cast_expression (CCodeExpression source_cexpr, DataType? expression_type, DataType? target_type, Expression? expr = null) {
		if (target_type is DelegateType && expression_type is MethodType) {
			var dt = (DelegateType) target_type;
			var mt = (MethodType) expression_type;

			var method = mt.method_symbol;
			if (method.base_method != null) {
				method = method.base_method;
			} else if (method.base_interface_method != null) {
				method = method.base_interface_method;
			}

			return new CCodeIdentifier (generate_delegate_wrapper (method, dt, expr));
		}

		return base.get_implicit_cast_expression (source_cexpr, expression_type, target_type, expr);
	}

	private string generate_delegate_wrapper (Method m, DelegateType dt, Expression? expr) {
		var d = dt.delegate_symbol;
		string delegate_name;
		var sig = d.parent_symbol as Signal;
		var dynamic_sig = sig as DynamicSignal;
		if (dynamic_sig != null) {
			delegate_name = get_dynamic_signal_cname (dynamic_sig);
		} else if (sig != null) {
			delegate_name = sig.parent_symbol.get_lower_case_cprefix () + sig.get_cname ();
		} else {
			delegate_name = Symbol.camel_case_to_lower_case (d.get_cname ());
		}

		string wrapper_name = "_%s_%s".printf (m.get_cname (), delegate_name);

		if (!add_wrapper (wrapper_name)) {
			// wrapper already defined
			return wrapper_name;
		}

		// declaration

		string return_type_cname = d.return_type.get_cname ();

		if (d.return_type.is_real_non_null_struct_type ()) {
			// structs are returned via out parameter
			return_type_cname = "void";
		}

		var function = new CCodeFunction (wrapper_name, return_type_cname);
		function.modifiers = CCodeModifiers.STATIC;
		m.ccodenode = function;

		var cparam_map = new HashMap<int,CCodeFormalParameter> (direct_hash, direct_equal);

		if (d.has_target) {
			var cparam = new CCodeFormalParameter ("self", "gpointer");
			cparam_map.set (get_param_pos (d.cinstance_parameter_position), cparam);
		}

		if (d.sender_type != null) {
			var param = new FormalParameter ("_sender", d.sender_type);
			generate_parameter (param, source_declarations, cparam_map, null);
		}

		var d_params = d.get_parameters ();
		foreach (FormalParameter param in d_params) {
			if (dynamic_sig != null
			    && param.variable_type is ArrayType
			    && ((ArrayType) param.variable_type).element_type.data_type == string_type.data_type) {
				// use null-terminated string arrays for dynamic signals for compatibility reasons
				param.no_array_length = true;
				param.array_null_terminated = true;
			}

			generate_parameter (param, source_declarations, cparam_map, null);
		}
		if (!d.no_array_length && d.return_type is ArrayType) {
			// return array length if appropriate
			var array_type = (ArrayType) d.return_type;

			for (int dim = 1; dim <= array_type.rank; dim++) {
				var cparam = new CCodeFormalParameter (get_array_length_cname ("result", dim), "int*");
				cparam_map.set (get_param_pos (d.carray_length_parameter_position + 0.01 * dim), cparam);
			}
		} else if (d.return_type is DelegateType) {
			// return delegate target if appropriate
			var deleg_type = (DelegateType) d.return_type;

			if (deleg_type.delegate_symbol.has_target) {
				var cparam = new CCodeFormalParameter (get_delegate_target_cname ("result"), "void**");
				cparam_map.set (get_param_pos (d.cdelegate_target_parameter_position), cparam);
			}
		} else if (d.return_type.is_real_non_null_struct_type ()) {
			var cparam = new CCodeFormalParameter ("result", "%s*".printf (d.return_type.get_cname ()));
			cparam_map.set (get_param_pos (-3), cparam);
		}

		if (m.get_error_types ().size > 0) {
			var cparam = new CCodeFormalParameter ("error", "GError**");
			cparam_map.set (get_param_pos (-1), cparam);
		}

		// append C parameters in the right order
		int last_pos = -1;
		int min_pos;
		while (true) {
			min_pos = -1;
			foreach (int pos in cparam_map.get_keys ()) {
				if (pos > last_pos && (min_pos == -1 || pos < min_pos)) {
					min_pos = pos;
				}
			}
			if (min_pos == -1) {
				break;
			}
			function.add_parameter (cparam_map.get (min_pos));
			last_pos = min_pos;
		}


		// definition

		var carg_map = new HashMap<int,CCodeExpression> (direct_hash, direct_equal);

		int i = 0;
		if (m.binding == MemberBinding.INSTANCE || m.closure) {
			CCodeExpression arg;
			if (d.has_target) {
				arg = new CCodeIdentifier ("self");
			} else {
				// use first delegate parameter as instance
				if (d_params.size == 0) {
					Report.error (expr != null ? expr.source_reference : null, "Cannot create delegate without target for instance method or closure");
					arg = new CCodeConstant ("NULL");
				} else {
					arg = new CCodeIdentifier ((d_params.get (0).ccodenode as CCodeFormalParameter).name);
					i = 1;
				}
			}
			carg_map.set (get_param_pos (m.cinstance_parameter_position), arg);
		}

		bool first = true;

		foreach (FormalParameter param in m.get_parameters ()) {
			if (first && d.sender_type != null && m.get_parameters ().size == d.get_parameters ().size + 1) {
				// sender parameter
				carg_map.set (get_param_pos (param.cparameter_position), new CCodeIdentifier ("_sender"));

				first = false;
				continue;
			}

			CCodeExpression arg;
			arg = new CCodeIdentifier ((d_params.get (i).ccodenode as CCodeFormalParameter).name);
			carg_map.set (get_param_pos (param.cparameter_position), arg);

			// handle array arguments
			if (!param.no_array_length && param.variable_type is ArrayType) {
				var array_type = (ArrayType) param.variable_type;
				for (int dim = 1; dim <= array_type.rank; dim++) {
					CCodeExpression clength;
					if (d_params.get (i).array_null_terminated) {
						requires_array_length = true;
						var len_call = new CCodeFunctionCall (new CCodeIdentifier ("_vala_array_length"));
						len_call.add_argument (new CCodeIdentifier (d_params.get (i).name));
						clength = len_call;
					} else if (d_params.get (i).no_array_length) {
						clength = new CCodeConstant ("-1");
					} else {
						clength = new CCodeIdentifier (get_parameter_array_length_cname (d_params.get (i), dim));
					}
					carg_map.set (get_param_pos (param.carray_length_parameter_position + 0.01 * dim), clength);
				}
			} else if (param.variable_type is DelegateType) {
				var deleg_type = (DelegateType) param.variable_type;

				if (deleg_type.delegate_symbol.has_target) {
					var ctarget = new CCodeIdentifier (get_delegate_target_cname (d_params.get (i).name));
					carg_map.set (get_param_pos (param.cdelegate_target_parameter_position), ctarget);
				}
			}

			i++;
		}
		if (!m.no_array_length && m.return_type is ArrayType) {
			var array_type = (ArrayType) m.return_type;
			for (int dim = 1; dim <= array_type.rank; dim++) {
				CCodeExpression clength;
				if (d.no_array_length) {
					clength = new CCodeConstant ("NULL");
				} else {
					clength = new CCodeIdentifier (get_array_length_cname ("result", dim));
				}
				carg_map.set (get_param_pos (m.carray_length_parameter_position + 0.01 * dim), clength);
			}
		} else if (m.return_type is DelegateType) {
			var deleg_type = (DelegateType) m.return_type;

			if (deleg_type.delegate_symbol.has_target) {
				var ctarget = new CCodeIdentifier (get_delegate_target_cname ("result"));
				carg_map.set (get_param_pos (m.cdelegate_target_parameter_position), ctarget);
			}
		} else if (m.return_type.is_real_non_null_struct_type ()) {
			carg_map.set (get_param_pos (-3), new CCodeIdentifier ("result"));
		}

		if (m.get_error_types ().size > 0) {
			carg_map.set (get_param_pos (-1), new CCodeIdentifier ("error"));
		}

		var ccall = new CCodeFunctionCall (new CCodeIdentifier (m.get_cname ()));

		// append C arguments in the right order
		last_pos = -1;
		while (true) {
			min_pos = -1;
			foreach (int pos in carg_map.get_keys ()) {
				if (pos > last_pos && (min_pos == -1 || pos < min_pos)) {
					min_pos = pos;
				}
			}
			if (min_pos == -1) {
				break;
			}
			ccall.add_argument (carg_map.get (min_pos));
			last_pos = min_pos;
		}

		var block = new CCodeBlock ();
		if (m.return_type is VoidType || m.return_type.is_real_non_null_struct_type ()) {
			block.add_statement (new CCodeExpressionStatement (ccall));
		} else {
			var cdecl = new CCodeDeclaration (return_type_cname);
			cdecl.add_declarator (new CCodeVariableDeclarator ("result", ccall));
			block.add_statement (cdecl);
		}

		if (d.has_target && !dt.value_owned && dt.is_called_once && expr != null) {
			// destroy notify "self" after the call, only support lambda expressions and methods
			CCodeExpression? destroy_notify = null;
			if (expr is LambdaExpression) {
				var lambda = (LambdaExpression) expr;
				if (lambda.method.closure) {
					int block_id = get_block_id (current_closure_block);
					destroy_notify = new CCodeIdentifier ("block%d_data_unref".printf (block_id));
				} else if (get_this_type () != null) {
					destroy_notify = get_destroy_func_expression (get_this_type ());
				} else if (in_constructor) {
					destroy_notify = new CCodeIdentifier ("g_object_unref");
				}
			} else if (expr.symbol_reference is Method) {
				var ma = (MemberAccess) expr;
				if (m.binding != MemberBinding.STATIC &&
				    !m.is_async_callback &&
				    ma.inner.value_type.data_type != null && ma.inner.value_type.data_type.is_reference_counting ()) {
					destroy_notify = get_destroy_func_expression (ma.inner.value_type);
				}
			}

			if (destroy_notify != null) {
				var unref_call = new CCodeFunctionCall (destroy_notify);
				unref_call.add_argument (new CCodeIdentifier ("self"));
				block.add_statement (new CCodeExpressionStatement (unref_call));
			}
		}

		if (!(m.return_type is VoidType || m.return_type.is_real_non_null_struct_type ())) {
			block.add_statement (new CCodeReturnStatement (new CCodeIdentifier ("result")));
		}

		// append to file

		source_declarations.add_type_member_declaration (function.copy ());

		function.block = block;
		source_type_member_definition.append (function);

		return wrapper_name;
	}

	public override void generate_parameter (FormalParameter param, CCodeDeclarationSpace decl_space, Map<int,CCodeFormalParameter> cparam_map, Map<int,CCodeExpression>? carg_map) {
		if (!(param.variable_type is DelegateType || param.variable_type is MethodType)) {
			base.generate_parameter (param, decl_space, cparam_map, carg_map);
			return;
		}

		string ctypename = param.variable_type.get_cname ();
		string target_ctypename = "void*";
		string target_destroy_notify_ctypename = "GDestroyNotify";

		if (param.parent_symbol is Delegate
		    && param.variable_type.get_cname () == ((Delegate) param.parent_symbol).get_cname ()) {
			// recursive delegate
			ctypename = "GCallback";
		}

		if (param.direction != ParameterDirection.IN) {
			ctypename += "*";
			target_ctypename += "*";
			target_destroy_notify_ctypename += "*";
		}

		param.ccodenode = new CCodeFormalParameter (get_variable_cname (param.name), ctypename);

		cparam_map.set (get_param_pos (param.cparameter_position), (CCodeFormalParameter) param.ccodenode);
		if (carg_map != null) {
			carg_map.set (get_param_pos (param.cparameter_position), get_variable_cexpression (param.name));
		}

		if (param.variable_type is DelegateType) {
			var deleg_type = (DelegateType) param.variable_type;
			var d = deleg_type.delegate_symbol;

			generate_delegate_declaration (d, decl_space);

			if (d.has_target) {
				var cparam = new CCodeFormalParameter (get_delegate_target_cname (get_variable_cname (param.name)), target_ctypename);
				cparam_map.set (get_param_pos (param.cdelegate_target_parameter_position), cparam);
				if (carg_map != null) {
					carg_map.set (get_param_pos (param.cdelegate_target_parameter_position), get_variable_cexpression (cparam.name));
				}
				if (deleg_type.value_owned) {
					cparam = new CCodeFormalParameter (get_delegate_target_destroy_notify_cname (get_variable_cname (param.name)), target_destroy_notify_ctypename);
					cparam_map.set (get_param_pos (param.cdelegate_target_parameter_position + 0.01), cparam);
					if (carg_map != null) {
						carg_map.set (get_param_pos (param.cdelegate_target_parameter_position + 0.01), get_variable_cexpression (cparam.name));
					}
				}
			}
		} else if (param.variable_type is MethodType) {
			var cparam = new CCodeFormalParameter (get_delegate_target_cname (get_variable_cname (param.name)), target_ctypename);
			cparam_map.set (get_param_pos (param.cdelegate_target_parameter_position), cparam);
			if (carg_map != null) {
				carg_map.set (get_param_pos (param.cdelegate_target_parameter_position), get_variable_cexpression (cparam.name));
			}
		}
	}
}
