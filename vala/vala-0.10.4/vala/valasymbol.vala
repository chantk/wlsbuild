/* valasymbol.vala
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
 * Represents a node in the symbol tree.
 */
public abstract class Vala.Symbol : CodeNode {
	/**
	 * The parent of this symbol.
	 */
	public weak Symbol? parent_symbol {
		get {
			if (owner == null) {
				return null;
			} else {
				return owner.owner;
			}
		}
	}

	/**
	 * The scope this symbol opens.
	 */
	public weak Scope owner {
		get {
			return _owner;
		}
		set {
			_owner = value;
			_scope.parent_scope = value;
		}
	}

	/**
	 * The GIR name.
	 */
	public string? gir_name {
		get {
			return _gir_name == null ? name : _gir_name;
		}
		set {
			_gir_name = value;
		}
	}

	/**
	 * The symbol name.
	 */
	public string? name { get; set; }

	/**
	 * Specifies whether this symbol is active.
	 *
	 * Symbols may become inactive when they only apply to a part of a
	 * scope. This is used for local variables not declared at the beginning
	 * of the block to determine which variables need to be freed before
	 * jump statements.
	 */
	public bool active { get; set; default = true; }

	/**
	 * Specifies whether this symbol has been deprecated.
	 */
	public bool deprecated { get; set; default = false; }

	/**
	 * Specifies what version this symbol has been deprecated since.
	 */
	public string? deprecated_since { get; set; default = null; }

	/**
	 * Specifies the replacement if this symbol has been deprecated.
	 */
	public string? replacement { get; set; default = null; }

	/**
	 * Specifies whether this symbol has been accessed.
	 */
	public bool used { get; set; }

	/**
	 * Specifies the accessibility of this symbol. Public accessibility
	 * doesn't limit access. Default accessibility limits access to this
	 * program or library. Private accessibility limits access to instances
	 * of the contained type.
	 */
	public SymbolAccessibility access { get; set; }

	public Comment? comment { get; set; }

	private List<string> cheader_filenames;

	/**
	 * Specifies whether this method explicitly hides a member of a base
	 * type.
	 */
	public bool hides { get; set; }

	/**
	 * Check if this symbol is just internal API (and therefore doesn't need 
	 * to be listed in header files for instance) by traversing parent symbols
	 * and checking their accessibility.
	 */
	public bool is_internal_symbol () {
		if (!external && external_package) {
			// non-external symbols in VAPI files are internal symbols
			return true;
		}

		for (Symbol sym = this; null != sym; sym = sym.parent_symbol) {
			if (sym.access == SymbolAccessibility.PRIVATE
			    || sym.access == SymbolAccessibility.INTERNAL) {
				return true;
			}
		}

		return false;
	}

	public bool is_private_symbol () {
		if (!external && external_package) {
			// non-external symbols in VAPI files are private symbols
			return true;
		}

		for (Symbol sym = this; null != sym; sym = sym.parent_symbol) {
			if (sym.access == SymbolAccessibility.PRIVATE) {
				return true;
			}
		}

		return false;
	}

	public Scope scope {
		get { return _scope; }
	}

	/**
	 * Specifies whether the implementation is external, for example in
	 * a separate C source file or in an external library.
	 */
	public bool external { get; set; }

	/**
	 * Specifies whether the implementation is in an external library.
	 */
	public bool external_package {
		get {
			return (source_reference != null && source_reference.file.external_package);
		}
	}

	private weak Scope _owner;
	private Scope _scope;
	private string? _gir_name = null;

	public Symbol (string? name, SourceReference? source_reference, Comment? comment = null) {
		this.name = name;
		this.source_reference = source_reference;
		this.comment = comment;
		_scope = new Scope (this);
	}
	
	/**
	 * Returns the fully expanded GIR name of this symbol
	 *
	 * @return full GIR name
	 */
	public string get_full_gir_name () {
		if (parent_symbol == null) {
			return gir_name;
		}
		
		if (name == null) {
			return parent_symbol.get_full_gir_name ();
		}

		if (parent_symbol.get_full_gir_name () == null) {
			return gir_name;
		}

		if (name.has_prefix (".")) {
			return "%s%s".printf (parent_symbol.get_full_gir_name (), gir_name);
		} else {
			return "%s.%s".printf (parent_symbol.get_full_gir_name (), gir_name);
		}
	}
	
	/**
	 * Returns the fully expanded name of this symbol for use in
	 * human-readable messages.
	 *
	 * @return full name
	 */
	public string get_full_name () {
		if (parent_symbol == null) {
			return name;
		}
		
		if (name == null) {
			return parent_symbol.get_full_name ();
		}

		if (parent_symbol.get_full_name () == null) {
			return name;
		}

		if (name.has_prefix (".")) {
			return "%s%s".printf (parent_symbol.get_full_name (), name);
		} else {
			return "%s.%s".printf (parent_symbol.get_full_name (), name);
		}
	}

	/**
	 * Returns the camel case string to be prepended to the name of members
	 * of this symbol when used in C code.
	 *
	 * @return the camel case prefix to be used in C code
	 */
	public virtual string get_cprefix () {
		if (name == null) {
			return "";
		} else {
			return name;
		}
	}
	
	/**
	 * Returns the C name of this symbol in lower case. Words are
	 * separated by underscores. The lower case C name of the parent symbol
	 * is prefix of the result, if there is one.
	 *
	 * @param infix a string to be placed between namespace and data type
	 *              name or null
	 * @return      the lower case name to be used in C code
	 */
	public virtual string? get_lower_case_cname (string? infix = null) {
		return null;
	}

	/**
	 * Returns the string to be prefixed to members of this symbol in
	 * lower case when used in C code.
	 *
	 * @return      the lower case prefix to be used in C code
	 */
	public virtual string get_lower_case_cprefix () {
		return "";
	}

	static List<string> _empty_string_list;

	/**
	 * Returns a list of C header filenames users of this symbol must
	 * include.
	 *
	 * @return list of C header filenames for this symbol
	 */
	public virtual List<string> get_cheader_filenames () {
		if (cheader_filenames == null || cheader_filenames.size == 0) {
			// parent_symbol can be null on incremental parsing
			if (parent_symbol != null) {
				/* default to header filenames of the namespace */
				var parent_header_filenames = parent_symbol.get_cheader_filenames ();
				if (parent_header_filenames.size > 0) {
					return parent_header_filenames;
				}
			}

			if (source_reference != null && !external_package) {
				// don't add default include directives for VAPI files
				add_cheader_filename (source_reference.file.get_cinclude_filename ());
			} else {
				if (_empty_string_list == null) {
					_empty_string_list = new ArrayList<string> ();
				}
				return _empty_string_list;
			}
		}
		return cheader_filenames;
	}

	/**
	 * Converts a string from CamelCase to lower_case.
	 *
	 * @param camel_case a string in camel case
	 * @return           the specified string converted to lower case
	 */
	public static string camel_case_to_lower_case (string camel_case) {
		if ("_" in camel_case) {
			// do not insert additional underscores if input is not real camel case
			return camel_case.down ();
		}

		var result_builder = new StringBuilder ("");

		weak string i = camel_case;

		bool first = true;
		while (i.length > 0) {
			unichar c = i.get_char ();
			if (c.isupper () && !first) {
				/* current character is upper case and
				 * we're not at the beginning */
				weak string t = i.prev_char ();
				bool prev_upper = t.get_char ().isupper ();
				t = i.next_char ();
				bool next_upper = t.get_char ().isupper ();
				if (!prev_upper || (i.length >= 2 && !next_upper)) {
					/* previous character wasn't upper case or
					 * next character isn't upper case*/
					long len = result_builder.str.length;
					if (len != 1 && result_builder.str.offset (len - 2).get_char () != '_') {
						/* we're not creating 1 character words */
						result_builder.append_c ('_');
					}
				}
			}
			
			result_builder.append_unichar (c.tolower ());
			
			first = false;
			i = i.next_char ();
		}
		
		return result_builder.str;
	}

	/**
	 * Converts a string from lower_case to CamelCase.
	 *
	 * @param lower_case a string in lower case
	 * @return           the specified string converted to camel case
	 */
	public static string lower_case_to_camel_case (string lower_case) {
		var result_builder = new StringBuilder ("");

		weak string i = lower_case;

		bool last_underscore = true;
		while (i.length > 0) {
			unichar c = i.get_char ();
			if (c == '_') {
				last_underscore = true;
			} else if (c.isupper ()) {
				// original string is not lower_case, don't apply transformation
				return lower_case;
			} else if (last_underscore) {
				result_builder.append_unichar (c.toupper ());
				last_underscore = false;
			} else {
				result_builder.append_unichar (c);
			}
			
			i = i.next_char ();
		}

		return result_builder.str;
	}

	// get the top scope from where this symbol is still accessible
	public Scope? get_top_accessible_scope (bool is_internal = false) {
		if (access == SymbolAccessibility.PRIVATE) {
			// private symbols are accessible within the scope where the symbol has been declared
			return owner;
		}

		if (access == SymbolAccessibility.INTERNAL) {
			is_internal = true;
		}

		if (parent_symbol == null) {
			// this is the root symbol
			if (is_internal) {
				// only accessible within the same library
				// return root scope
				return scope;
			} else {
				// unlimited access
				return null;
			}
		}

		// if this is a public symbol, it's equally accessible as the parent symbol
		return parent_symbol.get_top_accessible_scope (is_internal);
	}

	public virtual bool is_instance_member () {
		bool instance = true;
		if (this is Field) {
			var f = (Field) this;
			instance = (f.binding == MemberBinding.INSTANCE);
		} else if (this is Method) {
			var m = (Method) this;
			if (!(m is CreationMethod)) {
				instance = (m.binding == MemberBinding.INSTANCE);
			}
		} else if (this is Property) {
			var prop = (Property) this;
			instance = (prop.binding == MemberBinding.INSTANCE);
		} else if (this is EnumValue) {
			instance = false;
		} else if (this is ErrorCode) {
			instance = false;
		}

		return instance;
	}

	public virtual bool is_class_member () {
		bool isclass = true;
		if (this is Field) {
			var f = (Field) this;
			isclass = (f.binding == MemberBinding.CLASS);
		} else if (this is Method) {
			var m = (Method) this;
			if (!(m is CreationMethod)) {
				isclass = (m.binding == MemberBinding.CLASS);
			}
		} else if (this is Property) {
			var prop = (Property) this;
			isclass = (prop.binding == MemberBinding.CLASS);
		} else if (this is EnumValue) {
			isclass = false;
		} else if (this is ErrorCode) {
			isclass = false;
		}

		return isclass;
	}

	/**
	 * Process a [Deprecated] attribute
	 */
	public virtual void process_deprecated_attribute (Attribute attr) {
		if (attr.name != "Deprecated") {
			return;
		}

		deprecated = true;

		if (attr.has_argument ("since")) {
			deprecated_since = attr.get_string ("since");
		}
		if (attr.has_argument ("replacement")) {
			replacement = attr.get_string ("replacement");
		}
	}

	/**
	 * Check to see if the symbol has been deprecated, and emit a warning
	 * if it has.
	 */
	public bool check_deprecated (SourceReference? source_ref = null) {
		if (deprecated) {
			if (!CodeContext.get ().deprecated) {
				Report.warning (source_ref, "%s %s%s".printf (get_full_name (), (deprecated_since == null) ? "is deprecated" : "has been deprecated since %s".printf (deprecated_since), (replacement == null) ? "" : ". Use %s".printf (replacement)));
			}
			return true;
		} else {
			return false;
		}
	}

	/**
	 * Sets the C header filename of this namespace to the specified
	 * filename.
	 *
	 * @param cheader_filename header filename
	 */
	public void set_cheader_filename (string cheader_filename) {
		cheader_filenames = new ArrayList<string> ();
		cheader_filenames.add (cheader_filename);
	}

	/**
	 * Adds a filename to the list of C header filenames users of this data
	 * type must include.
	 *
	 * @param filename a C header filename
	 */
	public void add_cheader_filename (string filename) {
		if (cheader_filenames == null) {
			cheader_filenames = new ArrayList<string> ();
		}
		cheader_filenames.add (filename);
	}

	public Symbol? get_hidden_member () {
		Symbol sym = null;

		if (parent_symbol is Class) {
			var cl = ((Class) parent_symbol).base_class;
			while (cl != null) {
				sym = cl.scope.lookup (name);
				if (sym != null && sym.access != SymbolAccessibility.PRIVATE) {
					return sym;
				}
				cl = cl.base_class;
			}
		} else if (parent_symbol is Struct) {
			var st = ((Struct) parent_symbol).base_struct;
			while (st != null) {
				sym = st.scope.lookup (name);
				if (sym != null && sym.access != SymbolAccessibility.PRIVATE) {
					return sym;
				}
				st = st.base_struct;
			}
		}

		return null;
	}
}

public enum Vala.SymbolAccessibility {
	PRIVATE,
	INTERNAL,
	PROTECTED,
	PUBLIC
}

public enum MemberBinding {
	INSTANCE,
	CLASS,
	STATIC
}
