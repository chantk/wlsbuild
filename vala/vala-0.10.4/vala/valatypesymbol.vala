/* valatypesymbol.vala
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
 * Represents a runtime data type. This data type may be defined in Vala source
 * code or imported from an external library with a Vala API file.
 */
public abstract class Vala.TypeSymbol : Symbol {
	public TypeSymbol (string? name, SourceReference? source_reference = null, Comment? comment = null) {
		base (name, source_reference, comment);
	}

	/**
	 * Returns the name of this data type as it is used in C code.
	 *
	 * @return the name to be used in C code
	 */
	public abstract string get_cname (bool const_type = false);
	
	/**
	 * Checks whether this data type has value or reference type semantics.
	 *
	 * @return true if this data type has reference type semantics
	 */
	public virtual bool is_reference_type () {
		return false;
	}
	
	/**
	 * Returns the C function name that duplicates instances of this data
	 * type. The specified C function must accept one argument referencing
	 * the instance of this data type and return a reference to the
	 * duplicate.
	 *
	 * @return the name of the C function if supported or null otherwise
	 */
	public virtual string? get_dup_function () {
		return null;
	}
	
	/**
	 * Returns the C function name that frees instances of this data type.
	 * The specified C function must accept one argument pointing to the
	 * instance to be freed.
	 *
	 * @return the name of the C function if supported or null otherwise
	 */
	public virtual string? get_free_function () {
		return null;
	}

	/**
	 * Returns the C function name that copies contents of instances of
	 * this data type. This is only applicable to structs. The specified
	 * C function must accept two arguments, the first is the source value
	 * and the second is the destination value.
	 *
	 * @return the name of the C function if supported or null otherwise
	 */
	public virtual string? get_copy_function () {
		return null;
	}

	/**
	 * Returns the C function name that destroys the contents of instances
	 * of this data type. This is only applicable to structs. The specified
	 * C function must accept one argument pointing to the instance to be
	 * destroyed.
	 *
	 * @return the name of the C function if supported or null otherwise
	 */
	public virtual string? get_destroy_function () {
		return null;
	}

	/**
	 * Checks whether this data type supports reference counting. This is
	 * only valid for reference types.
	 *
	 * @return true if this data type supports reference counting
	 */
	public virtual bool is_reference_counting () {
		return false;
	}
	
	/**
	 * Returns the C function name that increments the reference count of
	 * instances of this data type. This is only valid for data types
	 * supporting reference counting. The specified C function must accept
	 * one argument referencing the instance of this data type and return
	 * the reference.
	 *
	 * @return the name of the C function or null if this data type does not
	 *         support reference counting
	 */
	public virtual string? get_ref_function () {
		return null;
	}
	
	/**
	 * Returns the C function name that decrements the reference count of
	 * instances of this data type. This is only valid for data types
	 * supporting reference counting. The specified C function must accept
	 * one argument referencing the instance of this data type.
	 *
	 * @return the name of the C function or null if this data type does not
	 *         support reference counting
	 */
	public virtual string? get_unref_function () {
		return null;
	}

	/**
	 * Returns the C function name that sinks the reference count of
	 * "floating" instances of this data type. This is only valid for data
	 * types supporting floating references. The specified C function must
	 * accept one argument referencing the instance of this data type and
	 * return a non-floating reference.
	 *
	 * The ref_sink function is called for any constructor of the class and
	 * for other methods that have the class as a return value and are
	 * marked with the 'floating' attribute.
	 *
	 * @return the name of the C function or null if this data type does not
	 *         support floating reference counts
	 */
	public virtual string? get_ref_sink_function () {
		return null;
	}

	/**
	 * Returns the C symbol representing the runtime type id for this data
	 * type. The specified symbol must express a registered GType.
	 *
	 * @return the name of the GType name in C code or null if this data
	 *         type is not registered with GType
	 */
	public virtual string? get_type_id () {
		return null;
	}
	
	/**
	 * Returns the name of this data type as used in C code marshallers
	 *
	 * @return type name for marshallers
	 */
	public virtual string? get_marshaller_type_name () {
		return null;
	}

	/**
	 * Returns the cname of the GValue parameter spec function.
	 */
	public virtual string? get_param_spec_function () {
		return null;
	}

	/**
	 * Returns the cname of the GValue getter function.
	 */
	public virtual string? get_get_value_function () {
		return null;
	}
	
	/**
	 * Returns the cname of the GValue setter function.
	 */
	public virtual string? get_set_value_function () {
		return null;
	}

	/**
	 * Returns the cname of the GValue taker function.
	 */
	public virtual string? get_take_value_function () {
		return null;
	}

	/**
	 * Returns the C name of this data type in upper case. Words are
	 * separated by underscores. The upper case C name of the namespace is
	 * prefix of the result.
	 *
	 * @param infix a string to be placed between namespace and data type
	 *              name or null
	 * @return      the upper case name to be used in C code
	 */
	public virtual string? get_upper_case_cname (string? infix = null) {
		return null;
	}

	/**
	 * Returns the default value for the given type. Returning null means
	 * there is no default value (i.e. not that the default name is NULL).
	 *
	 * @return the name of the default value
	 */
	public virtual string? get_default_value () {
		return null;
	}

	/**
	 * Checks whether this data type is equal to or a subtype of the
	 * specified data type.
	 *
	 * @param t a data type
	 * @return  true if t is a supertype of this data type, false otherwise
	 */
	public virtual bool is_subtype_of (TypeSymbol t) {
		return (this == t);
	}
	
	/**
	 * Return the index of the specified type parameter name.
	 */
	public virtual int get_type_parameter_index (string name) {
		return -1;
	}
}
