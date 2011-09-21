/* valadelegate.vala
 *
 * Copyright (C) 2006-2010  Jürg Billeter
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
 */

using GLib;

/**
 * Represents a function callback type.
 */
public class Vala.Delegate : TypeSymbol {
	/**
	 * The return type of this callback.
	 */
	public DataType return_type {
		get { return _return_type; }
		set {
			_return_type = value;
			_return_type.parent_node = this;
		}
	}

	/**
	 * Specifies whether callback supports calling instance methods.
	 * The reference to the object instance will be appended to the end of
	 * the argument list in the generated C code.
	 */
	public bool has_target { get; set; }

	public DataType? sender_type { get; set; }

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

	private List<TypeParameter> type_parameters = new ArrayList<TypeParameter> ();

	private List<FormalParameter> parameters = new ArrayList<FormalParameter> ();
	private string cname;

	private DataType _return_type;

	/**
	 * Creates a new delegate.
	 *
	 * @param name        delegate type name
	 * @param return_type return type
	 * @param source      reference to source code
	 * @return            newly created delegate
	 */
	public Delegate (string? name, DataType return_type, SourceReference? source_reference = null, Comment? comment = null) {
		base (name, source_reference, comment);
		this.return_type = return_type;

		// error is -1 (right of user_data)
		cinstance_parameter_position = -2;
		carray_length_parameter_position = -3;
		cdelegate_target_parameter_position = -3;
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

	public List<TypeParameter> get_type_parameters () {
		return type_parameters;
	}

	public override int get_type_parameter_index (string name) {
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
	 * Appends paramater to this callback function.
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
		scope.add (param.name, param);
	}

	/**
	 * Return copy of parameter list.
	 *
	 * @return parameter list
	 */
	public List<FormalParameter> get_parameters () {
		return parameters;
	}
	
	/**
	 * Checks whether the arguments and return type of the specified method
	 * matches this callback.
	 *
	 * @param m a method
	 * @return  true if the specified method is compatible to this callback
	 */
	public bool matches_method (Method m, DataType dt) {
		if (m.coroutine) {
			// async delegates are not yet supported
			return false;
		}

		// method is allowed to ensure stricter return type (stronger postcondition)
		if (!m.return_type.stricter (return_type.get_actual_type (dt, null, this))) {
			return false;
		}
		
		var method_params = m.get_parameters ();
		Iterator<FormalParameter> method_params_it = method_params.iterator ();

		if (sender_type != null && method_params.size == parameters.size + 1) {
			// method has sender parameter
			method_params_it.next ();

			// method is allowed to accept arguments of looser types (weaker precondition)
			var method_param = method_params_it.get ();
			if (!sender_type.stricter (method_param.variable_type)) {
				return false;
			}
		}

		bool first = true;
		foreach (FormalParameter param in parameters) {
			/* use first callback parameter as instance parameter if
			 * an instance method is being compared to a static
			 * callback
			 */
			if (first && m.binding == MemberBinding.INSTANCE && !has_target) {
				first = false;
				continue;
			}

			/* method is allowed to accept less arguments */
			if (!method_params_it.next ()) {
				break;
			}

			// method is allowed to accept arguments of looser types (weaker precondition)
			var method_param = method_params_it.get ();
			if (!param.variable_type.get_actual_type (dt, null, this).stricter (method_param.variable_type)) {
				return false;
			}
		}
		
		/* method may not expect more arguments */
		if (method_params_it.next ()) {
			return false;
		}
		
		return true;
	}

	public override void accept (CodeVisitor visitor) {
		visitor.visit_delegate (this);
	}

	public override void accept_children (CodeVisitor visitor) {
		foreach (TypeParameter p in type_parameters) {
			p.accept (visitor);
		}
		
		return_type.accept (visitor);
		
		foreach (FormalParameter param in parameters) {
			param.accept (visitor);
		}

		foreach (DataType error_type in get_error_types ()) {
			error_type.accept (visitor);
		}
	}

	public override string get_cname (bool const_type = false) {
		if (cname == null) {
			cname = "%s%s".printf (parent_symbol.get_cprefix (), name);
		}
		return cname;
	}

	/**
	 * Sets the name of this callback as it is used in C code.
	 *
	 * @param cname the name to be used in C code
	 */
	public void set_cname (string cname) {
		this.cname = cname;
	}

	public override string? get_lower_case_cname (string? infix) {
		if (infix == null) {
			infix = "";
		}
		return "%s%s%s".printf (parent_symbol.get_lower_case_cprefix (), infix, camel_case_to_lower_case (name));
	}

	public override string? get_upper_case_cname (string? infix) {
		return get_lower_case_cname (infix).up ();
	}

	private void process_ccode_attribute (Attribute a) {
		if (a.has_argument ("cname")) {
			set_cname (a.get_string ("cname"));
		}
		if (a.has_argument ("has_target")) {
			has_target = a.get_bool ("has_target");
		}
		if (a.has_argument ("instance_pos")) {
			cinstance_parameter_position = a.get_double ("instance_pos");
		}
		if (a.has_argument ("array_length")) {
			no_array_length = !a.get_bool ("array_length");
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
		if (a.has_argument ("cheader_filename")) {
			var val = a.get_string ("cheader_filename");
			foreach (string filename in val.split (",")) {
				add_cheader_filename (filename);
			}
		}
	}
	
	/**
	 * Process all associated attributes.
	 */
	public void process_attributes () {
		foreach (Attribute a in attributes) {
			if (a.name == "CCode") {
				process_ccode_attribute (a);
			} else if (a.name == "Deprecated") {
				process_deprecated_attribute (a);
			}
		}
	}

	public override bool is_reference_type () {
		return false;
	}

	public override string? get_type_id () {
		return "G_TYPE_POINTER";
	}

	public override string? get_marshaller_type_name () {
		return "POINTER";
	}

	public override string? get_get_value_function () {
		return "g_value_get_pointer";
	}
	
	public override string? get_set_value_function () {
		return "g_value_set_pointer";
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

	public string get_prototype_string (string name) {
		return "%s %s %s".printf (get_return_type_string (), name, get_parameters_string ());
	}

	string get_return_type_string () {
		string str = "";
		if (!return_type.value_owned && return_type is ReferenceType) {
			str = "weak ";
		}
		str += return_type.to_string ();

		return str;
	}

	string get_parameters_string () {
		string str = "(";

		int i = 1;
		foreach (FormalParameter param in parameters) {
			if (i > 1) {
				str += ", ";
			}

			if (param.direction == ParameterDirection.IN) {
				if (param.variable_type.value_owned) {
					str += "owned ";
				}
			} else {
				if (param.direction == ParameterDirection.REF) {
					str += "ref ";
				} else if (param.direction == ParameterDirection.OUT) {
					str += "out ";
				}
				if (!param.variable_type.value_owned && param.variable_type is ReferenceType) {
					str += "weak ";
				}
			}

			str += param.variable_type.to_string ();

			i++;
		}

		str += ")";

		return str;
	}

	public override bool check (SemanticAnalyzer analyzer) {
		if (checked) {
			return !error;
		}

		checked = true;

		process_attributes ();

		var old_source_file = analyzer.current_source_file;

		if (source_reference != null) {
			analyzer.current_source_file = source_reference.file;
		}

		foreach (TypeParameter p in type_parameters) {
			p.check (analyzer);
		}
		
		return_type.check (analyzer);
		
		foreach (FormalParameter param in parameters) {
			param.check (analyzer);
		}

		foreach (DataType error_type in get_error_types ()) {
			error_type.check (analyzer);
		}

		analyzer.current_source_file = old_source_file;

		return !error;
	}
}
