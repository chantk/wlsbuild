/* valaattribute.vala
 *
 * Copyright (C) 2006-2008  Jürg Billeter
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
 * Represents an attribute specified in the source code.
 */
public class Vala.Attribute : CodeNode {
	/**
	 * The name of the attribute type.
	 */
	public string name { get; set; }

	/**
	 * Contains all specified attribute arguments.
	 */
	public Vala.Map<string,Expression> args = new HashMap<string,Expression> (str_hash, str_equal);

	/**
	 * Creates a new attribute.
	 *
	 * @param name             attribute type name
	 * @param source_reference reference to source code
	 * @return                 newly created attribute
	 */
	public Attribute (string name, SourceReference? source_reference = null) {
		this.name = name;
		this.source_reference = source_reference;
	}

	/**
	 * Adds an attribute argument.
	 *
	 * @param arg named argument
	 */
	public void add_argument (string key, Expression value) {
		args.set (key, value);
	}
	
	/**
	 * Returns whether this attribute has the specified named argument.
	 *
	 * @param name argument name
	 * @return     true if the argument has been found, false otherwise
	 */
	public bool has_argument (string name) {
		return args.contains (name);
	}
	
	/**
	 * Returns the string value of the specified named argument.
	 *
	 * @param name argument name
	 * @return     string value
	 */
	public string? get_string (string name) {
		var lit = args.get (name) as StringLiteral;
		if (lit != null) {
			return lit.eval ();
		}
		
		return null;
	}
	
	/**
	 * Returns the integer value of the specified named argument.
	 *
	 * @param name argument name
	 * @return     integer value
	 */
	public int get_integer (string name) {
		var lit = args.get (name) as IntegerLiteral;
		if (lit != null) {
			return lit.value.to_int ();
		}
		
		return 0;
	}

	/**
	 * Returns the double value of the specified named argument.
	 *
	 * @param name argument name
	 * @return     double value
	 */
	public double get_double (string name) {
		var arg = args.get (name);
		if (arg is RealLiteral) {
			var lit = (RealLiteral) arg;
			return lit.value.to_double ();
		} else if (arg is IntegerLiteral) {
			var lit = (IntegerLiteral) arg;
			return lit.value.to_int ();
		} else if (arg is UnaryExpression) {
			var unary = (UnaryExpression) arg;
			if (unary.operator == UnaryOperator.MINUS) {
				if (unary.inner is RealLiteral) {
					var lit = (RealLiteral) unary.inner;
					return -lit.value.to_double ();
				} else if (unary.inner is IntegerLiteral) {
					var lit = (IntegerLiteral) unary.inner;
					return -lit.value.to_int ();
				}
			}
		}
		
		return 0;
	}

	/**
	 * Returns the boolean value of the specified named argument.
	 *
	 * @param name argument name
	 * @return     boolean value
	 */
	public bool get_bool (string name) {
		var lit = args.get (name) as BooleanLiteral;
		if (lit != null) {
			return lit.value;
		}
		
		return false;
	}
}
