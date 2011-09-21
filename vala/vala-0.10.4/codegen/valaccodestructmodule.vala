/* valaccodestructmodule.vala
 *
 * Copyright (C) 2006-2009  Jürg Billeter
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

using GLib;

public class Vala.CCodeStructModule : CCodeBaseModule {
	public override void generate_struct_declaration (Struct st, CCodeDeclarationSpace decl_space) {
		if (decl_space.add_symbol_declaration (st, st.get_cname ())) {
			return;
		}

		if (st.is_boolean_type ()) {
			// typedef for boolean types
			decl_space.add_include ("stdbool.h");
			st.set_cname ("bool");
			return;
		} else if (st.is_integer_type ()) {
			// typedef for integral types
			decl_space.add_include ("stdint.h");
			st.set_cname ("%sint%d_t".printf (st.signed ? "" : "u", st.width));
			return;
		} else if (st.is_floating_type ()) {
			// typedef for floating types
			st.set_cname (st.width == 64 ? "double" : "float");
			return;
		}

		if (context.profile == Profile.GOBJECT) {
			if (st.has_type_id) {
				decl_space.add_type_declaration (new CCodeNewline ());
				var macro = "(%s_get_type ())".printf (st.get_lower_case_cname (null));
				decl_space.add_type_declaration (new CCodeMacroReplacement (st.get_type_id (), macro));

				var type_fun = new StructRegisterFunction (st, context);
				type_fun.init_from_type (false);
				decl_space.add_type_member_declaration (type_fun.get_declaration ());
			}
		}

		var instance_struct = new CCodeStruct ("_%s".printf (st.get_cname ()));
		instance_struct.deprecated = st.deprecated;

		foreach (Field f in st.get_fields ()) {
			string field_ctype = f.variable_type.get_cname ();
			if (f.is_volatile) {
				field_ctype = "volatile " + field_ctype;
			}

			if (f.binding == MemberBinding.INSTANCE)  {
				generate_type_declaration (f.variable_type, decl_space);

				instance_struct.add_field (field_ctype, f.get_cname () + f.variable_type.get_cdeclarator_suffix (), f.deprecated ? " G_GNUC_DEPRECATED" : null);
				if (f.variable_type is ArrayType && !f.no_array_length) {
					// create fields to store array dimensions
					var array_type = (ArrayType) f.variable_type;

					if (!array_type.fixed_length) {
						var len_type = int_type.copy ();

						for (int dim = 1; dim <= array_type.rank; dim++) {
							instance_struct.add_field (len_type.get_cname (), get_array_length_cname (f.name, dim));
						}

						if (array_type.rank == 1 && f.is_internal_symbol ()) {
							instance_struct.add_field (len_type.get_cname (), get_array_size_cname (f.name));
						}
					}
				} else if (f.variable_type is DelegateType) {
					var delegate_type = (DelegateType) f.variable_type;
					if (delegate_type.delegate_symbol.has_target) {
						// create field to store delegate target
						instance_struct.add_field ("gpointer", get_delegate_target_cname (f.name));
						if (delegate_type.value_owned) {
							instance_struct.add_field ("GDestroyNotify", get_delegate_target_destroy_notify_cname (f.name));
						}
					}
				}
			}
		}

		if (st.base_struct == null) {
			decl_space.add_type_declaration (new CCodeTypeDefinition ("struct _%s".printf (st.get_cname ()), new CCodeVariableDeclarator (st.get_cname ())));

			decl_space.add_type_definition (instance_struct);
		} else {
			decl_space.add_type_declaration (new CCodeTypeDefinition (st.base_struct.get_cname (), new CCodeVariableDeclarator (st.get_cname ())));
		}

		var function = new CCodeFunction (st.get_dup_function (), st.get_cname () + "*");
		if (st.is_private_symbol ()) {
			function.modifiers = CCodeModifiers.STATIC;
		}
		function.add_parameter (new CCodeFormalParameter ("self", "const " + st.get_cname () + "*"));
		decl_space.add_type_member_declaration (function);

		function = new CCodeFunction (st.get_free_function (), "void");
		if (st.is_private_symbol ()) {
			function.modifiers = CCodeModifiers.STATIC;
		}
		function.add_parameter (new CCodeFormalParameter ("self", st.get_cname () + "*"));
		decl_space.add_type_member_declaration (function);

		if (st.is_disposable ()) {
			function = new CCodeFunction (st.get_copy_function (), "void");
			if (st.is_private_symbol ()) {
				function.modifiers = CCodeModifiers.STATIC;
			}
			function.add_parameter (new CCodeFormalParameter ("self", "const " + st.get_cname () + "*"));
			function.add_parameter (new CCodeFormalParameter ("dest", st.get_cname () + "*"));
			decl_space.add_type_member_declaration (function);

			function = new CCodeFunction (st.get_destroy_function (), "void");
			if (st.is_private_symbol ()) {
				function.modifiers = CCodeModifiers.STATIC;
			}
			function.add_parameter (new CCodeFormalParameter ("self", st.get_cname () + "*"));
			decl_space.add_type_member_declaration (function);
		}
	}

	public override void visit_struct (Struct st) {
		push_context (new EmitContext (st));

		var old_instance_finalize_fragment = instance_finalize_fragment;
		instance_finalize_fragment = new CCodeFragment ();

		generate_struct_declaration (st, source_declarations);

		if (!st.is_internal_symbol ()) {
			generate_struct_declaration (st, header_declarations);
		}
		if (!st.is_private_symbol ()) {
			generate_struct_declaration (st, internal_header_declarations);
		}

		st.accept_children (this);

		if (context.profile == Profile.GOBJECT && !st.is_boolean_type () && !st.is_integer_type () && !st.is_floating_type ()) {
			if (st.is_disposable ()) {
				add_struct_copy_function (st);
				add_struct_destroy_function (st);
			}

			add_struct_dup_function (st);
			add_struct_free_function (st);
		}

		instance_finalize_fragment = old_instance_finalize_fragment;

		pop_context ();
	}

	void add_struct_dup_function (Struct st) {
		var function = new CCodeFunction (st.get_dup_function (), st.get_cname () + "*");
		if (st.access == SymbolAccessibility.PRIVATE) {
			function.modifiers = CCodeModifiers.STATIC;
		}

		function.add_parameter (new CCodeFormalParameter ("self", "const " + st.get_cname () + "*"));

		var cblock = new CCodeBlock ();

		var cdecl = new CCodeDeclaration (st.get_cname () + "*");
		cdecl.add_declarator (new CCodeVariableDeclarator ("dup"));
		cblock.add_statement (cdecl);

		var creation_call = new CCodeFunctionCall (new CCodeIdentifier ("g_new0"));
		creation_call.add_argument (new CCodeConstant (st.get_cname ()));
		creation_call.add_argument (new CCodeConstant ("1"));
		cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (new CCodeIdentifier ("dup"), creation_call)));

		if (st.is_disposable ()) {
			var copy_call = new CCodeFunctionCall (new CCodeIdentifier (st.get_copy_function ()));
			copy_call.add_argument (new CCodeIdentifier ("self"));
			copy_call.add_argument (new CCodeIdentifier ("dup"));
			cblock.add_statement (new CCodeExpressionStatement (copy_call));
		} else {
			source_declarations.add_include ("string.h");

			var sizeof_call = new CCodeFunctionCall (new CCodeIdentifier ("sizeof"));
			sizeof_call.add_argument (new CCodeConstant (st.get_cname ()));

			var copy_call = new CCodeFunctionCall (new CCodeIdentifier ("memcpy"));
			copy_call.add_argument (new CCodeIdentifier ("dup"));
			copy_call.add_argument (new CCodeIdentifier ("self"));
			copy_call.add_argument (sizeof_call);
			cblock.add_statement (new CCodeExpressionStatement (copy_call));
		}

		cblock.add_statement (new CCodeReturnStatement (new CCodeIdentifier ("dup")));

		function.block = cblock;

		source_type_member_definition.append (function);
	}

	void add_struct_free_function (Struct st) {
		var function = new CCodeFunction (st.get_free_function (), "void");
		if (st.access == SymbolAccessibility.PRIVATE) {
			function.modifiers = CCodeModifiers.STATIC;
		}

		function.add_parameter (new CCodeFormalParameter ("self", st.get_cname () + "*"));

		var cblock = new CCodeBlock ();

		if (st.is_disposable ()) {
			var destroy_call = new CCodeFunctionCall (new CCodeIdentifier (st.get_destroy_function ()));
			destroy_call.add_argument (new CCodeIdentifier ("self"));
			cblock.add_statement (new CCodeExpressionStatement (destroy_call));
		}

		var free_call = new CCodeFunctionCall (new CCodeIdentifier ("g_free"));
		free_call.add_argument (new CCodeIdentifier ("self"));
		cblock.add_statement (new CCodeExpressionStatement (free_call));

		function.block = cblock;

		source_type_member_definition.append (function);
	}

	void add_struct_copy_function (Struct st) {
		var function = new CCodeFunction (st.get_copy_function (), "void");
		if (st.access == SymbolAccessibility.PRIVATE) {
			function.modifiers = CCodeModifiers.STATIC;
		}

		function.add_parameter (new CCodeFormalParameter ("self", "const " + st.get_cname () + "*"));
		function.add_parameter (new CCodeFormalParameter ("dest", st.get_cname () + "*"));

		var cblock = new CCodeBlock ();
		var cfrag = new CCodeFragment ();
		cblock.add_statement (cfrag);

		foreach (var f in st.get_fields ()) {
			if (f.binding == MemberBinding.INSTANCE) {
				CCodeExpression copy = new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), f.name);
				if (requires_copy (f.variable_type))  {
					var this_access = new MemberAccess.simple ("this");
					this_access.value_type = get_data_type_for_symbol ((TypeSymbol) f.parent_symbol);
					this_access.ccodenode = new CCodeIdentifier ("(*self)");
					var ma = new MemberAccess (this_access, f.name);
					ma.symbol_reference = f;
					copy = get_ref_cexpression (f.variable_type, copy, ma, f);
					if (copy == null) {
						// error case, continue to avoid critical
						continue;
					}
				}
				var dest = new CCodeMemberAccess.pointer (new CCodeIdentifier ("dest"), f.name);

				var array_type = f.variable_type as ArrayType;
				if (array_type != null && array_type.fixed_length) {
					// fixed-length (stack-allocated) arrays
					source_declarations.add_include ("string.h");

					var sizeof_call = new CCodeFunctionCall (new CCodeIdentifier ("sizeof"));
					sizeof_call.add_argument (new CCodeIdentifier (array_type.element_type.get_cname ()));
					var size = new CCodeBinaryExpression (CCodeBinaryOperator.MUL, new CCodeConstant ("%d".printf (array_type.length)), sizeof_call);

					var array_copy_call = new CCodeFunctionCall (new CCodeIdentifier ("memcpy"));
					array_copy_call.add_argument (dest);
					array_copy_call.add_argument (copy);
					array_copy_call.add_argument (size);
					cblock.add_statement (new CCodeExpressionStatement (array_copy_call));
				} else {
					cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (dest, copy)));

					if (array_type != null) {
						for (int dim = 1; dim <= array_type.rank; dim++) {
							var len_src = new CCodeMemberAccess.pointer (new CCodeIdentifier ("self"), get_array_length_cname (f.name, dim));
							var len_dest = new CCodeMemberAccess.pointer (new CCodeIdentifier ("dest"), get_array_length_cname (f.name, dim));
							cblock.add_statement (new CCodeExpressionStatement (new CCodeAssignment (len_dest, len_src)));
						}
					}
				}
			}
		}

		append_temp_decl (cfrag, temp_vars);
		temp_vars.clear ();

		function.block = cblock;

		source_type_member_definition.append (function);
	}

	void add_struct_destroy_function (Struct st) {
		var function = new CCodeFunction (st.get_destroy_function (), "void");
		if (st.access == SymbolAccessibility.PRIVATE) {
			function.modifiers = CCodeModifiers.STATIC;
		}

		function.add_parameter (new CCodeFormalParameter ("self", st.get_cname () + "*"));

		var cblock = new CCodeBlock ();

		cblock.add_statement (instance_finalize_fragment);

		function.block = cblock;

		source_type_member_definition.append (function);
	}
}

