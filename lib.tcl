namespace eval targets {}
namespace eval build {}

proc program {name commands} {
    namespace eval ::targets::$name {
	set type programs
	set working_dir .
    }
    proc ::targets::${name}::do {} $commands
}

proc in-directory {dir args} {
    set space [uplevel namespace current]
    if {$args == {}} {
	append ${space}::working_dir "/$dir"
    } else {
	set tmp [set ${space}::working_dir]
	append ${space}::working_dir $dir
	uplevel $args
	set ${space}::working_dir $tmp
    }
}

proc uses {args} {
    foreach x $args {
	uplevel ::targets::${x}::do
    }
}

proc c {args} {
    set space [uplevel namespace current]
    switch [lindex $args 0] {
	define {
	    foreach x [lrange $args 1 end] {
		lappend ${space}::cppflags -D$x
	    }
	}
	libs {
	    foreach x [lrange $args 1 end] {
		lappend ${space}::libs -l$x
	    }
	}
	needs {
	    lappend ${space}::cflags -std=[lindex $args 1]
	}
	sources {
	    foreach x [lrange $args 1 end] {
		lappend ${space}::csources [set ${space}::working_dir]/$x
		lappend ${space}::objects [regsub {\.c$} $x .o]
	    }
	}
    }
}

proc targets {args} {
    switch [lindex $args 0] {
	are {
	    foreach x [lrange $args 1 end] {
		lappend ::build::targets $x
	    }
	}
	default {
	    foreach x [lrange $args 1 end] {
		lappend ::build::defaults $x
	    }
	}
    }
}
proc readvar {v} {
    if {[info exists $v]} {
	return [set $v]
    } else {
	return ""
    }
}

proc system {arg} {
    puts $arg
    exec sh -c $arg
}

proc main {} {
    set ::build::do_targets $::build::defaults
    foreach x $::build::do_targets {
	::targets::${x}::do
    }
    foreach x $::build::do_targets {
	foreach y [readvar ::targets::${x}::csources] {
	    system [concat gcc -c [readvar ::targets::${x}::cflags] [readvar ::targets::${x}::cppflags] $y]
	}
    }
    foreach x $::build::do_targets {
	system [concat gcc [readvar ::targets::${x}::cflags] [readvar ::targets::${x}::objects] [readvar ::targets::${x}::libs] -o $x]
    }
}
