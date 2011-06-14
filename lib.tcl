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

array set solvers {}
proc solve {args} {
    global solvers
    for {set i [expr {[llength $args]-1}]} {$i >= 0} {incr i -1} {
	if {[info exists solvers([lrange $args 0 $i])]} {
	    uplevel $solvers([lrange $args 0 $i]) [lrange $args [expr {$i+1}] end]
	    return
	}
    }
    puts stderr [array get solvers]
    puts stderr "Could not find solver for $args."
    exit 1
}

proc solution {name arg commands} {
    global solvers
    uplevel [list proc $name $arg $commands]
    set solvers($name) [uplevel namespace which $name]
}

proc solved {name commands} {
    global solvers
    uplevel $commands
    set solvers($name) [list apply [list {} $commands]]
    uplevel return
}

proc solvewith {solver name} {
    uplevel "proc $name {args} {uplevel solve $solver \$args}"
    uplevel namespace export $name
}

proc solvewith_map {solver name} {
    uplevel "proc $name {args} {foreach x \$args {uplevel solve $solver \$x}}"
    uplevel namespace export $name
}

namespace eval c {
    namespace export define libs test needs sources
    proc define {args} {
	set space [uplevel namespace current]
	foreach x $args {
	    lappend ${space}::cppflags -D$x
	}
    }

    namespace eval needs {
	solvewith ::c::c99 c99
	solvewith_map libs libs
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
	    namespace upvar ::groups::${x} csources csources cflags cflags cc cc cppflags cppflags
	    puts $outfile ": foreach $csources |> ^ CC %f^ $cc [readvar cflags] [readvar cppflags]-c %f -o %o|> ${x}_%B.o {${x}-objs}"
	}
    }

    proc link {outfile} {
	foreach x $::build::do_targets {
	    if {[readvar ::groups::${x}::linkwith] == "c"} {
		namespace upvar ::groups::${x} cflags cflags cc cc libs libs
		puts $outfile ": {${x}-objs} |> ^ CCLD %o^ $cc [readvar cflags] %f [readvar libs] -o %o |> $x"
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

solution libs {libname} {
    puts -nonewline stderr "Testing for $libname with pkg-config...   "
    if {![catch {exec pkg-config --exists $libname}]} {
	puts yes
	solved "libs $libname" [concat "set libname $libname;" {
	    set space [uplevel namespace current]
	    lappend ${space}::cflags [exec pkg-config --cflags $libname]
	    lappend ${space}::libs [exec pkg-config --libs $libname]}]
    } else {
	puts no
    }
    solved "libs $libname" [concat "set libname $libname;" {
	set space [uplevel namespace current]
	lappend ${space}::libs -lgc}]
}

solution ::c::c99 {} {
    puts stderr "Testing for c99...   Making a stupid assumption."
    solved ::c::c99 {
	set space [uplevel namespace current]
	set ${space}::cc "gcc -std=c99"
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
