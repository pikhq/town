namespace eval targets {}
namespace eval build {}

proc program {name commands} {
    namespace eval ::targets::$name {
	set type programs
	set working_dir ..
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

namespace eval c {
    namespace export define libs needs sources
    proc define {args} {
	set space [uplevel namespace current]
	foreach x $args {
	    lappend ${space}::cppflags -D$x
	}
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
		lappend ${space}::libs -l$x
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
	    namespace upvar ::targets::${x} csources csources cflags cflags cppflags cppflags
	    puts $outfile ": foreach $csources |> ^ CC %f^ gcc [readvar cflags] [readvar cppflags]-c %f -o %o|> ${x}_%B.o {${x}-objs}"
	}
    }

    proc link {outfile} {
	foreach x $::build::do_targets {
	    if {[readvar ::targets::${x}::linkwith] == "c"} {
		namespace upvar ::targets::${x} cflags cflags libs libs
		puts $outfile ": {${x}-objs} |> ^ CCLD %o^ gcc [readvar cflags] %f [readvar libs] -o %o |> $x"
	    }
	}
    }

    namespace ensemble create
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
    if {[uplevel info exists $v]} {
	return [uplevel set $v]
    } else {
	return ""
    }
}

proc system {arg} {
    puts $arg
    exec sh -c $arg
}

proc main {} {
    set outfile [open objs/Tupfile w]
    set ::build::do_targets $::build::defaults
    foreach x $::build::do_targets {
	::targets::${x}::do
    }
    ::c::generate $outfile
    ::c::link $outfile
    close $outfile
}

namespace eval c {
}
