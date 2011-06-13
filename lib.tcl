namespace eval groups {}
namespace eval build {}

proc program {name commands} {
    lappend ::build::possible_targets $name
    namespace eval ::groups::$name {
	set type programs
	set working_dir ..
    }
    proc ::groups::${name}::do {} $commands
}

proc module {name commands} {
    lappend ::build::possible_targets $name
    namespace eval ::groups::$name {
	set type module
	set working_dir ..
    }
    proc ::groups::${name}:: do {} $commands
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
	uplevel ::groups::${x}::do
    }
}

namespace eval c {
    namespace export define libs test needs sources
    proc define {args} {
	set space [uplevel namespace current]
	foreach x $args {
	    lappend ${space}::cppflags -D$x
	}
    }

    namespace eval test {
	namespace export pkg-config
	proc pkg-config {x if else} {
	    puts -nonewline stderr "Testing for $x with pkg-config...   "
	    if {![catch {exec pkg-config --exists $x}]} {
		puts yes
		uplevel $if
	    } else {
		puts no
		uplevel $else
	    }
	}
	namespace ensemble create
    }

    namespace eval needs {
	namespace export c99 libs
	proc c99 {} {
	    set space [uplevel namespace current]
	    lappend ${space}::cflags -std=c99
	}

	proc libs {args} {
	    set space [uplevel namespace current]
	    foreach x $args {
		if {[info commands ::c::needs::lib_$x] != ""} {
		    return [uplevel c needs lib_$x]
		}
		c test pkg-config $x {
		    lappend ${space}::libs [exec pkg-config --libs $x]
		    lappend ${space}::cflags [exec pkg-config --cflags $x]
		} {
		    lappend ${space}::libs -l$x
		}
	    }
	}
	namespace ensemble create
    }

    proc sources {args} {
	set space [uplevel namespace current]
	if {[set ${space}::type] != "modules" && ![info exists ${space}::linkwith]} {
	    set ${space}::linkwith c
	}
	foreach x $args {
	    lappend ${space}::csources [set ${space}::working_dir]/$x
	}
    }

    proc generate {outfile} {
	foreach x $::build::do_targets {
	    namespace upvar ::groups::${x} csources csources cflags cflags cppflags cppflags
	    puts $outfile ": foreach $csources |> ^ CC %f^ gcc [readvar cflags] [readvar cppflags]-c %f -o %o|> ${x}_%B.o {${x}-objs}"
	}
    }

    proc link {outfile} {
	foreach x $::build::do_targets {
	    if {[readvar ::groups::${x}::linkwith] == "c"} {
		namespace upvar ::groups::${x} cflags cflags libs libs
		puts $outfile ": {${x}-objs} |> ^ CCLD %o^ gcc [readvar cflags] %f [readvar libs] -o %o |> $x"
	    }
	}
    }

    namespace ensemble create
}

namespace eval targets {
    namespace export are default
    proc are {args} {
	foreach x $args {
	    lappend ::build::targets $x
	}
    }

    proc default {args} {
	foreach x $args {
	    lappend ::build::defaults $x
	}
    }
    namespace ensemble create
}

proc readvar {v} {
    if {[uplevel info exists $v]} {
	return [uplevel set $v]
    } else {
	return ""
    }
}

proc main {} {
    set outfile [open objs/Tupfile w]
    if {[info exists ::build::defaults]} {
	set ::build::do_targets $::build::defaults
    } else {
	set ::build::do_targets $::build::possible_targets
    }
    foreach x $::build::do_targets {
	::groups::${x}::do
    }
    ::c::generate $outfile
    ::c::link $outfile
    close $outfile
}
