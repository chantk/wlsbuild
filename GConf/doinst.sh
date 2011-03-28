config() {
  NEW="$1"
  OLD="$(dirname $NEW)/$(basename $NEW .new)"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
    # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

config etc/gconf/2/path.new
config etc/gconf/2/evoldap.conf.new
config etc/dbus-1/system.d/org.gnome.GConf.Defaults.conf.new

if [ -x usr/bin/glib-compile-schemas -a -d usr/share/glib-2.0/schemas ]; then
    usr/bin/glib-compile-schemas usr/share/glib-2.0/schemas
fi

if ps acx | grep -q gconfd-2 ; then
  killall -HUP gconfd-2 ;
fi
