/* valamethod.vala
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

using GLib;

/**
 * Represents a type or namespace method.
 */
public class Vala.Method : Symbol {
	List<TypeParameter> type_parameters = new ArrayList<TypeParameter> ();

	public const string DEFAULT_SENTINEL = "NULL";

	/**
	 * The return type of this method.
	 */
	public DataType return_type {
		get { return _return_type; }
		set {
			_return_type = value;
			_return_type.parent_node = this;
		}
	}
	
	public Block body {
		get { return _body; }
		set {
			_body = value;
			if (_body != null) {
				_body.owner = scope;
			}
		}
	}

	public BasicBlock entry_block { get; set; }

	public BasicBlock return_block { get; set; }

	public BasicBlock exit_block { get; set; }

	/**
	 * Specifies whether this method may only be called with an instance of
	 * the contained type.
	 */
	public MemberBinding binding { get; set; default = MemberBinding.INSTANCE; }

	/**
	 * The name of the vfunc of this method as it is used in C code.
	 */
	public string vfunc_name {
		get {
			if (_vfunc_name == null) {
				_vfunc_name = this.name;
			}
			return _vfunc_name;
		}
		set {
			_vfunc_name = value;
		}
	}

	/**
	 * The sentinel to use for terminating variable length argument lists.
	 */
	public string sentinel {
		get {
			if (_sentinel == null) {
				return DEFAULT_SENTINEL;
			}

			return _sentinel;
		}

		set {
			_sentinel = value;
		}
	}
	
	/**
	 * Specifies whether this method is abstract. Abstract methods have no
	 * body, may only be specified within abstract classes, and must be
	 * overriden by derived non-abstract classes.
	 */
	public bool is_abstract { get; set; }
	
	/**
	 * Specifies whether this method is virtual. Virtual methods may be
	 * overridden by derived classes.
	 */
	public bool is_virtual { get; set; }
	
	/**
	 * Specifies whether this method overrides a virtual or abstract method
	 * of a base type.
	 */
	public bool overrides { get; set; }
	
	/**
	 * Specifies whether this method should be inlined.
	 */
	public bool is_inline { get; set; }

	public bool returns_floating_reference { get; set; }

	/**
	 * Specifies whether the C method returns a new instance pointer which
	 * may be different from the previous instance pointer. Only valid for
	 * imported methods.
	 */
	public bool returns_modified_pointer { get; set; }

	/**
	 * Specifies the virtual or abstract method this method overrides.
	 * Reference must be weak as virtual and abstract methods set 
	 * base_method to themselves.
	 */
	public Method base_method {
		get {
			find_base_methods ();
			return _base_method;
		}
	}
	
	/**
	 * Specifies the abstract interface method this method implements.
	 */
	public Method base_interface_method {
		get {
			find_base_methods ();
			return _base_interface_method;
		}
	}

	public bool entry_point { get; private set; }

	/**
	 * Specifies the generated `this` parameter for instance methods.
	 */
	public FormalParameter this_parameter { get; set; }

	/**
	 * Specifies the generated `result` variable for postconditions.
	 */
	public LocalVariable result_var { get; set; }

	/**
	 * Specifies the position of the instance parameter in the C function.
	 */
	public double cinstance_parameter_position { get; set; }

	/**
	 * Specifies the position of the array length out parameter in the C
	 * function.
	 */
	public double carray_length_parameter_position { get; set; }

	/**
	 * Specifies the position of the delegate target out parameter in the C
	 * function.
	 */
	public double cdelegate_target_parameter_position { get; set; }

	/**
	 * Specifies whether the array length should be returned implicitly
	 * if the return type is an array.
	 */
	public bool no_array_length { get; set; }

	/**
	 * Specifies whether the array is null terminated.
	 */
	public bool array_null_terminated { get; set; }

	/**
	 * Specified a custom type for the array length parameter.
	 */
	public string? array_length_type { get; set; default = null; }

	/**
	 * Specifies whether this method expects printf-style format arguments.
	 */
	public bool printf_format { get; set; }

	/**
	 * Specifies whether this method expects scanf-style format arguments.
	 */
	public bool scanf_format { get; set; }

	/**
	 * Specifies whether a new function without a GType parameter is
	 * available. This is only applicable to creation methods.
	 */
	public bool has_new_function { get; set; default = true; }

	/**
	 * Specifies whether a construct function with a GType parameter is
	 * available. This is only applicable to creation methods.
	 */
	public bool has_construct_function { get; set; default = true; }

	public bool has_generic_type_parameter { get; set; }

	public double generic_type_parameter_position { get; set; }

	public bool simple_generics { get; set; }

	public weak Signal signal_reference { get; set; }

	public bool closure { get; set; }

	public bool coroutine { get; set; }

	public bool is_async_callback { get; set; }

	private List<FormalParameter> parameters = new ArrayList<FormalParameter> ();
	private string cname;
	private string finish_name;
	private string _vfunc_name;
	private string _sentinel;
	private List<Expression> preconditions = new ArrayList<Expression> ();
	private List<Expression> postconditions = new ArrayList<Expression> ();
	private DataType _return_type;
	private Block _body;

	private weak Method _base_method;
	private Method _base_interface_method;
	private bool base_methods_valid;

	Method? callback_method;

	// only valid for closures
	List<LocalVariable> captured_variables;

	/**
	 * Creates a new method.
	 *
	 * @param name        method name
	 * @param return_type method return type
	 * @param source      reference to source code
	 * @return            newly created method
	 */
	public Method (string? name, DataType return_type, SourceReference? source_reference = null, Comment? comment = null) {
		base (name, source_reference, comment);
		this.return_type = return_type;

		carray_length_parameter_position = -3;
		cdelegate_target_parameter_position = -3;
	}

	/**
	 * Appends parameter to this method.
	 *
	 * @param param a formal parameter
	 */
	public void add_parameter (FormalParameter param) {
		// default C parameter position
		param.cparameter_position = parameters.size + 1;
		param.carray_length_parameter_position = param.cparameter_position + 0.1;
		param.cdelegate_target_parameter_position = param.cparameter_position + 0.1;
		param.cdestroy_notify_parameter_position = param.cparameter_position + 0.1;

		parameters.add (param);
		if (!param.ellipsis) {
			scope.add (param.name, param);
		}
	}
	
	public List<FormalParameter> get_parameters () {
		return parameters;
	}

	/**
	 * Remove all parameters from this method.
	 */
	public void clear_parameters () {
		foreach (FormalParameter param in parameters) {
			if (!param.ellipsis) {
				scope.remove (param.name);
			}
		}
		parameters.clear ();
	}

	public override void accept (CodeVisitor visitor) {
		visitor.visit_method (this);
	}

	public override void accept_children (CodeVisitor visitor) {
		foreach (TypeParameter p in get_type_parameters ()) {
			p.accept (visitor);
		}

		if (return_type != null) {
			return_type.accept (visitor);
		}

		foreach (FormalParameter param in parameters) {
			param.accept (visitor);
		}

		foreach (DataType error_type in get_error_types ()) {
			error_type.accept (visitor);
		}

		if (result_var != null) {
			result_var.accept (visitor);
		}

		foreach (Expression precondition in preconditions) {
			precondition.accept (visitor);
		}

		foreach (Expression postcondition in postconditions) {
			postcondition.accept (visitor);
		}

		if (body != null) {
			body.accept (visitor);
		}
	}

	/**
	 * Returns the interface name of this method as it is used in C code.
	 *
	 * @return the name to be used in C code
	 */
	public string get_cname () {
		if (cname == null) {
			cname = get_default_cname ();
		}
		return cname;
	}

	public string get_finish_cname () {
		assert (coroutine);
		if (finish_name == null) {
			finish_name = get_default_finish_cname ();
		}
		return finish_name;
	}

	public void set_finish_cname (string name) {
		finish_name = name;
	}

	/**
	 * Returns the default interface name of this method as it is used in C
	 * code.
	 *
	 * @return the name to be used in C code by default
	 */
	public virtual string get_default_cname () {
		if (name == "main" && parent_symbol.name == null) {
			// avoid conflict with generated main function
			return "_vala_main";
		} else if (name.has_prefix ("_")) {
			return "_%s%s".printf (parent_symbol.get_lower_case_cprefix (), name.offset (1));
		} else {
			return "%s%s".printf (parent_symbol.get_lower_case_cprefix (), name);
		}
	}

	/**
	 * Returns the implementation name of this data type as it is used in C
	 * code.
	 *
	 * @return the name to be used in C code
	 */
	public virtual string get_real_cname () {
		if (base_method != null || base_interface_method != null) {
			return "%sreal_%s".printf (parent_symbol.get_lower_case_cprefix (), name);
		} else {
			return get_cname ();
		}
	}

	protected string get_finish_name_for_basename (string basename) {
		string result = basename;
		if (result.has_suffix ("_async")) {
			result = result.substring (0, result.length - "_async".length);
		}
		result += "_finish";
		return result;
	}

	public string get_finish_real_cname () {
		assert (coroutine);
		return get_finish_name_for_basename (get_real_cname ());
	}

	public string get_finish_vfunc_name () {
		assert (coroutine);
		return get_finish_name_for_basename (vfunc_name);
	}

	public string get_default_finish_cname () {
		return get_finish_name_for_basename (get_cname ());
	}
	
	/**
	 * Sets the name of this method as it is used in C code.
	 *
	 * @param cname the name to be used in C code
	 */
	public void set_cname (string cname) {
		this.cname = cname;
	}
	
	private void process_ccode_attribute (Attribute a) {
		if (a.has_argument ("cname")) {
			set_cname (a.get_string ("cname"));
		}
		if (a.has_argument ("cheader_filename")) {
			var val = a.get_string ("cheader_filename");
			foreach (string filename in val.split (",")) {
				add_cheader_filename (filename);
			}
		}
		if (a.has_argument ("vfunc_name")) {
			this.vfunc_name = a.get_string ("vfunc_name");
		}
		if (a.has_argument ("finish_name")) {
			this.finish_name = a.get_string ("finish_name");
		}
		if (a.has_argument ("sentinel")) {
			this.sentinel = a.get_string ("sentinel");
		}
		if (a.has_argument ("instance_pos")) {
			cinstance_parameter_position = a.get_double ("instance_pos");
		}
		if (a.has_argument ("array_length")) {
			no_array_length = !a.get_bool ("array_length");
		}
		if (a.has_argument ("array_length_type")) {
			array_length_type = a.get_string ("array_length_type");
		}
		if (a.has_argument ("array_null_terminated")) {
			array_null_terminated = a.get_bool ("array_null_terminated");
		}
		if (a.has_argument ("array_length_pos")) {
			carray_length_parameter_position = a.get_double ("array_length_pos");
		}
		if (a.has_argument ("delegate_target_pos")) {
			cdelegate_target_parameter_position = a.get_double ("delegate_target_pos");
		}
		if (a.has_argument ("has_new_function")) {
			has_new_function = a.get_bool ("has_new_function");
		}
		if (a.has_argument ("has_construct_function")) {
			has_construct_function = a.get_bool ("has_construct_function");
		}
		if (a.has_argument ("generic_type_pos")) {
			has_generic_type_parameter = true;
			generic_type_parameter_position = a.get_double ("generic_type_pos");
		}
		if (a.has_argument ("simple_generics")) {
			simple_generics = a.get_bool ("simple_generics");
		}
		if (a.has_argument ("returns_floating_reference")) {
			returns_floating_reference = a.get_bool ("returns_floating_reference");
		}
	}
	
	/**
	 * Process all associated attributes.
	 */
	public void process_attributes () {
		foreach (Attribute a in attributes) {
			if (a.name == "CCode") {
				process_ccode_attribute (a);
			} else if (a.name == "ReturnsModifiedPointer") {
				returns_modified_pointer = true;
			} else if (a.name == "FloatingReference") {
				return_type.floating_reference = true;
			} else if (a.name == "PrintfFormat") {
				printf_format = true;
			} else if (a.name == "ScanfFormat") {
				scanf_format = true;
			} else if (a.name == "NoArrayLength") {
				Report.warning (source_reference, "NoArrayLength attribute is deprecated, use [CCode (array_length = false)] instead.");
				no_array_length = true;
			} else if (a.name == "Deprecated") {
				process_deprecated_attribute (a);
			} else if (a.name == "NoThrow") {
				get_error_types ().clear ();
			}
		}
	}

	/**
	 * Checks whether the parameters and return type of this method are
	 * compatible with the specified method
	 *
	 * @param base_method a method
	 * @param invalid_match error string about which check failed
	 * @return true if the specified method is compatible to this method
	 */
	public bool compatible (Method base_method, out string? invalid_match) {
		if (binding != base_method.binding) {
			invalid_match = "incompatible binding";
			return false;
		}

		ObjectType object_type = null;
		if (parent_symbol is ObjectTypeSymbol) {
			object_type = new ObjectType ((ObjectTypeSymbol) parent_symbol);
			foreach (TypeParameter type_parameter in object_type.type_symbol.get_type_parameters ()) {
				var type_arg = new GenericType (type_parameter);
				type_arg.value_owned = true;
				object_type.add_type_argument (type_arg);
			}
		}

		var actual_base_type = base_method.return_type.get_actual_type (object_type, null, this);
		if (!return_type.equals (actual_base_type)) {
			invalid_match = "incompatible return type";
			return false;
		}
		
		Iterator<FormalParameter> method_params_it = parameters.iterator ();
		int param_index = 1;
		foreach (FormalParameter base_param in base_method.parameters) {
			/* this method may not expect less arguments */
			if (!method_params_it.next ()) {
				invalid_match = "too few parameters";
				return false;
			}
			
			actual_base_type = base_param.variable_type.get_actual_type (object_type, null, this);
			if (!actual_base_type.equals (method_params_it.get ().variable_type)) {
				invalid_match = "incompatible type of parameter %d".printf (param_index);
				return false;
			}
			param_index++;
		}
		
		/* this method may not expect more arguments */
		if (method_params_it.next ()) {
			invalid_match = "too many parameters";
			return false;
		}

		/* this method may throw less but not more errors than the base method */
		foreach (DataType method_error_type in get_error_types ()) {
			bool match = false;
			foreach (DataType base_method_error_type in base_method.get_error_types ()) {
				if (method_error_type.compatible (base_method_error_type)) {
					match = true;
					break;
				}
			}

			if (!match) {
				invalid_match = "incompatible error type `%s'".printf (method_error_type.to_string ());
				return false;
			}
		}
		if (base_method.coroutine != this.coroutine) {
			invalid_match = "async mismatch";
			return false;
		}

		return true;
	}

	/**
	 * Appends the specified parameter to the list of type parameters.
	 *
	 * @param p a type parameter
	 */
	public void add_type_parameter (TypeParameter p) {
		type_parameters.add (p);
		scope.add (p.name, p);
	}

	/**
	 * Returns a copy of the type parameter list.
	 *
	 * @return list of type parameters
	 */
	public List<TypeParameter> get_type_parameters () {
		return type_parameters;
	}

	public int get_type_parameter_index (string name) {
		int i = 0;
		foreach (TypeParameter parameter in type_parameters) {
			if (parameter.name == name) {
				return i;
			}
			i++;
		}
		return -1;
	}

	/**
	 * Adds a precondition to this method.
	 *
	 * @param precondition a boolean precondition expression
	 */
	public void add_precondition (Expression precondition) {
		preconditions.add (precondition);
		precondition.parent_node = this;
	}

	/**
	 * Returns a copy of the list of preconditions of this method.
	 *
	 * @return list of preconditions
	 */
	public List<Expression> get_preconditions () {
		return preconditions;
	}

	/**
	 * Adds a postcondition to this method.
	 *
	 * @param postcondition a boolean postcondition expression
	 */
	public void add_postcondition (Expression postcondition) {
		postconditions.add (postcondition);
		postcondition.parent_node = this;
	}

	/**
	 * Returns a copy of the list of postconditions of this method.
	 *
	 * @return list of postconditions
	 */
	public List<Expression> get_postconditions () {
		return postconditions;
	}

	public override void replace_type (DataType old_type, DataType new_type) {
		if (return_type == old_type) {
			return_type = new_type;
			return;
		}
		var error_types = get_error_types ();
		for (int i = 0; i < error_types.size; i++) {
			if (error_types[i] == old_type) {
				error_types[i] = new_type;
				return;
			}
		}
	}

	private void find_base_methods () {
		if (base_methods_valid) {
			return;
		}

		if (parent_symbol is Class) {
			if (!(this is CreationMethod)) {
				find_base_interface_method ((Class) parent_symbol);
				if (is_virtual || is_abstract || overrides) {
					find_base_class_method ((Class) parent_symbol);
				}
			}
		} else if (parent_symbol is Interface) {
			if (is_virtual || is_abstract) {
				_base_interface_method = this;
			}
		}

		base_methods_valid = true;
	}

	private void find_base_class_method (Class cl) {
		var sym = cl.scope.lookup (name);
		if (sym is Method) {
			var base_method = (Method) sym;
			if (base_method.is_abstract || base_method.is_virtual) {
				string invalid_match;
				if (!compatible (base_method, out invalid_match)) {
					error = true;
					Report.error (source_reference, "overriding method `%s' is incompatible with base method `%s': %s.".printf (get_full_name (), base_method.get_full_name (), invalid_match));
					return;
				}

				_base_method = base_method;
				return;
			}
		} else if (sym is Signal) {
			var sig = (Signal) sym;
			if (sig.is_virtual) {
				var base_method = sig.default_handler;
				string invalid_match;
				if (!compatible (base_method, out invalid_match)) {
					error = true;
					Report.error (source_reference, "overriding method `%s' is incompatible with base method `%s': %s.".printf (get_full_name (), base_method.get_full_name (), invalid_match));
					return;
				}

				_base_method = base_method;
				return;
			}
		}

		if (cl.base_class != null) {
			find_base_class_method (cl.base_class);
		}
	}

	private void find_base_interface_method (Class cl) {
		// FIXME report error if multiple possible base methods are found
		foreach (DataType type in cl.get_base_types ()) {
			if (type.data_type is Interface) {
				var sym = type.data_type.scope.lookup (name);
				if (sym is Method) {
					var base_method = (Method) sym;
					if (base_method.is_abstract || base_method.is_virtual) {
						string invalid_match;
						if (!compatible (base_method, out invalid_match)) {
							error = true;
							Report.error (source_reference, "overriding method `%s' is incompatible with base method `%s': %s.".printf (get_full_name (), base_method.get_full_name (), invalid_match));
							return;
						}

						_base_interface_method = base_method;
						return;
					}
				}
			}
		}
	}

	public override bool check (SemanticAnalyzer analyzer) {
		if (checked) {
			return !error;
		}

		checked = true;

		process_attributes ();

		if (is_abstract) {
			if (parent_symbol is Class) {
				var cl = (Class) parent_symbol;
				if (!cl.is_abstract) {
					error = true;
					Report.error (source_reference, "Abstract methods may not be declared in non-abstract classes");
					return false;
				}
			} else if (!(parent_symbol is Interface)) {
				error = true;
				Report.error (source_reference, "Abstract methods may not be declared outside of classes and interfaces");
				return false;
			}
		} else if (is_virtual) {
			if (!(parent_symbol is Class) && !(parent_symbol is Interface)) {
				error = true;
				Report.error (source_reference, "Virtual methods may not be declared outside of classes and interfaces");
				return false;
			}

			if (parent_symbol is Class) {
				var cl = (Class) parent_symbol;
				if (cl.is_compact) {
					Report.error (source_reference, "Virtual methods may not be declared in compact classes");
					return false;
				}
			}
		} else if (overrides) {
			if (!(parent_symbol is Class)) {
				error = true;
				Report.error (source_reference, "Methods may not be overridden outside of classes");
				return false;
			}
		} else if (access == SymbolAccessibility.PROTECTED) {
			if (!(parent_symbol is Class) && !(parent_symbol is Interface)) {
				error = true;
				Report.error (source_reference, "Protected methods may not be declared outside of classes and interfaces");
				return false;
			}
		}

		if (is_abstract && body != null) {
			Report.error (source_reference, "Abstract methods cannot have bodies");
		} else if ((is_abstract || is_virtual) && external && !external_package && !parent_symbol.external) {
			Report.error (source_reference, "Extern methods cannot be abstract or virtual");
		} else if (external && body != null) {
			Report.error (source_reference, "Extern methods cannot have bodies");
		} else if (!is_abstract && !external && !external_package && body == null) {
			Report.error (source_reference, "Non-abstract, non-extern methods must have bodies");
		}

		if (coroutine && !external_package && !analyzer.context.has_package ("gio-2.0")) {
			error = true;
			Report.error (source_reference, "gio-2.0 package required for async methods");
			return false;
		}

		var old_source_file = analyzer.current_source_file;
		var old_symbol = analyzer.current_symbol;

		if (source_reference != null) {
			analyzer.current_source_file = source_reference.file;
		}
		analyzer.current_symbol = this;

		return_type.check (analyzer);

		var init_attr = get_attribute ("ModuleInit");
		if (init_attr != null) {
			source_reference.file.context.module_init_method = this;
		}

		if (return_type != null) {
			return_type.check (analyzer);
		}

		if (parameters.size == 1 && parameters[0].ellipsis && body != null) {
			// accept just `...' for external methods for convenience
			error = true;
			Report.error (parameters[0].source_reference, "Named parameter required before `...'");
		}

		foreach (FormalParameter param in parameters) {
			param.check (analyzer);
			if (coroutine && param.direction == ParameterDirection.REF) {
				error = true;
				Report.error (param.source_reference, "Reference parameters are not supported for async methods");
			}
		}

		foreach (DataType error_type in get_error_types ()) {
			error_type.check (analyzer);
		}

		if (result_var != null) {
			result_var.check (analyzer);
		}

		foreach (Expression precondition in preconditions) {
			precondition.check (analyzer);
		}

		foreach (Expression postcondition in postconditions) {
			postcondition.check (analyzer);
		}

		if (body != null) {
			body.check (analyzer);
		}

		analyzer.current_source_file = old_source_file;
		analyzer.current_symbol = old_symbol;

		if (analyzer.current_struct != null) {
			if (is_abstract || is_virtual || overrides) {
				Report.error (source_reference, "A struct member `%s' cannot be marked as override, virtual, or abstract".printf (get_full_name ()));
				return false;
			}
		} else if (overrides && base_method == null) {
			Report.error (source_reference, "%s: no suitable method found to override".printf (get_full_name ()));
		}

		if (!external_package && !overrides && !hides && get_hidden_member () != null) {
			Report.warning (source_reference, "%s hides inherited method `%s'. Use the `new' keyword if hiding was intentional".printf (get_full_name (), get_hidden_member ().get_full_name ()));
		}

		// check whether return type is at least as accessible as the method
		if (!analyzer.is_type_accessible (this, return_type)) {
			error = true;
			Report.error (source_reference, "return type `%s` is less accessible than method `%s`".printf (return_type.to_string (), get_full_name ()));
			return false;
		}

		foreach (Expression precondition in get_preconditions ()) {
			if (precondition.error) {
				// if there was an error in the precondition, skip this check
				error = true;
				return false;
			}

			if (!precondition.value_type.compatible (analyzer.bool_type)) {
				error = true;
				Report.error (precondition.source_reference, "Precondition must be boolean");
				return false;
			}
		}

		foreach (Expression postcondition in get_postconditions ()) {
			if (postcondition.error) {
				// if there was an error in the postcondition, skip this check
				error = true;
				return false;
			}

			if (!postcondition.value_type.compatible (analyzer.bool_type)) {
				error = true;
				Report.error (postcondition.source_reference, "Postcondition must be boolean");
				return false;
			}
		}

		// check that all errors that can be thrown in the method body are declared
		if (body != null) { 
			foreach (DataType body_error_type in body.get_error_types ()) {
				bool can_propagate_error = false;
				foreach (DataType method_error_type in get_error_types ()) {
					if (body_error_type.compatible (method_error_type)) {
						can_propagate_error = true;
					}
				}
				bool is_dynamic_error = body_error_type is ErrorType && ((ErrorType) body_error_type).dynamic_error;
				if (!can_propagate_error && !is_dynamic_error) {
					Report.warning (body_error_type.source_reference, "unhandled error `%s'".printf (body_error_type.to_string()));
				}
			}
		}

		if (is_possible_entry_point (analyzer)) {
			if (analyzer.context.entry_point != null) {
				error = true;
				Report.error (source_reference, "program already has an entry point `%s'".printf (analyzer.context.entry_point.get_full_name ()));
				return false;
			}
			entry_point = true;
			analyzer.context.entry_point = this;

			if (tree_can_fail && analyzer.context.profile != Profile.DOVA) {
				Report.error (source_reference, "\"main\" method cannot throw errors");
			}
		}

		return !error;
	}

	bool is_possible_entry_point (SemanticAnalyzer analyzer) {
		if (external_package) {
			return false;
		}

		if (analyzer.context.entry_point_name == null) {
			if (name == null || name != "main") {
				// method must be called "main"
				return false;
			}
		} else {
			// custom entry point name
			if (get_full_name () != analyzer.context.entry_point_name) {
				return false;
			}
		}
		
		if (binding == MemberBinding.INSTANCE) {
			// method must be static
			return false;
		}
		
		if (return_type is VoidType) {
		} else if (return_type.data_type == analyzer.int_type.data_type) {
		} else {
			// return type must be void or int
			return false;
		}
		
		var params = get_parameters ();
		if (params.size == 0) {
			// method may have no parameters
			return true;
		}

		if (params.size > 1) {
			// method must not have more than one parameter
			return false;
		}
		
		Iterator<FormalParameter> params_it = params.iterator ();
		params_it.next ();
		var param = params_it.get ();

		if (param.direction == ParameterDirection.OUT) {
			// parameter must not be an out parameter
			return false;
		}
		
		if (!(param.variable_type is ArrayType)) {
			// parameter must be an array
			return false;
		}
		
		var array_type = (ArrayType) param.variable_type;
		if (array_type.element_type.data_type != analyzer.string_type.data_type) {
			// parameter must be an array of strings
			return false;
		}
		
		return true;
	}

	public int get_required_arguments () {
		int n = 0;
		foreach (var param in parameters) {
			if (param.initializer != null || param.ellipsis) {
				// optional argument
				break;
			}
			n++;
		}
		return n;
	}

	public Method get_callback_method () {
		assert (this.coroutine);

		if (callback_method == null) {
			var bool_type = new BooleanType ((Struct) CodeContext.get ().root.scope.lookup ("bool"));
			bool_type.value_owned = true;
			callback_method = new Method ("callback", bool_type, source_reference);
			callback_method.access = SymbolAccessibility.PUBLIC;
			callback_method.external = true;
			callback_method.binding = MemberBinding.INSTANCE;
			callback_method.owner = scope;
			callback_method.is_async_callback = true;
			callback_method.set_cname (get_real_cname () + "_co");
		}
		return callback_method;
	}

	public List<FormalParameter> get_async_begin_parameters () {
		assert (this.coroutine);

		var glib_ns = CodeContext.get ().root.scope.lookup ("GLib");

		var params = new ArrayList<FormalParameter> ();
		foreach (var param in parameters) {
			if (param.direction == ParameterDirection.IN) {
				params.add (param);
			}
		}

		var callback_type = new DelegateType ((Delegate) glib_ns.scope.lookup ("AsyncReadyCallback"));
		callback_type.nullable = true;
		callback_type.is_called_once = true;

		var callback_param = new FormalParameter ("_callback_", callback_type);
		callback_param.initializer = new NullLiteral (source_reference);
		callback_param.cparameter_position = -1;
		callback_param.cdelegate_target_parameter_position = -0.9;

		params.add (callback_param);

		return params;
	}

	public List<FormalParameter> get_async_end_parameters () {
		assert (this.coroutine);

		var params = new ArrayList<FormalParameter> ();

		var glib_ns = CodeContext.get ().root.scope.lookup ("GLib");
		var result_type = new ObjectType ((ObjectTypeSymbol) glib_ns.scope.lookup ("AsyncResult"));

		var result_param = new FormalParameter ("_res_", result_type);
		result_param.cparameter_position = 0.1;
		params.add (result_param);

		foreach (var param in parameters) {
			if (param.direction == ParameterDirection.OUT) {
				params.add (param);
			}
		}

		return params;
	}

	public void add_captured_variable (LocalVariable local) {
		assert (this.closure);

		if (captured_variables == null) {
			captured_variables = new ArrayList<LocalVariable> ();
		}
		captured_variables.add (local);
	}

	public void get_captured_variables (Collection<LocalVariable> variables) {
		if (captured_variables != null) {
			foreach (var local in captured_variables) {
				variables.add (local);
			}
		}
	}

	public override void get_defined_variables (Collection<LocalVariable> collection) {
		// capturing variables is only supported if they are initialized
		// therefore assume that captured variables are initialized
		if (closure) {
			get_captured_variables (collection);
		}
	}
}

// vim:sw=8 noet
