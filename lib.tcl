namespace eval groups {}
namespace eval build {}

proc gen_space {name type commands} {
    lappend ::build::possible_targets $name
    namespace eval ::groups::$name set type $type
    namespace eval ::groups::$name {
	set working_dir ..
	proc flag_set {flag val} {variable $flag;set $flag $val}
	proc flag_read {flag} {variable $flag;if {![info exists $flag]} {return ""} else {return set $flag}}
	proc flag_append {flag val} {variable $flag;lappend $flag $val}
    }
    proc ::groups::${name}::do {} $commands
}

proc program {name commands} {
    gen_space $name program $commands
}

proc module {name commands} {
    gen_space $name module $commands
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

proc current {} {
    return [uplevel 2 namespace current]
}

namespace eval c {
    namespace export define libs test needs sources
    proc define {args} {
	foreach x $args {
	    [current]::flag_append cppflags -D$x
	}
    }

    namespace eval needs {
	solvewith ::c::c99 c99
	solvewith_map libs libs
	namespace ensemble create
    }

    proc sources {args} {
	set space [uplevel namespace current]
	if {[[current]::flag_read type] != "modules" && ![info exists [current]::linkwith]} {
	    [current]::flag_set linkwith c
	}
	foreach x $args {
	    [current]::flag_append csources [[current]::flag_read working_dir]/$x
	}
    }

    proc generate {outfile} {
	foreach x $::build::do_targets {
	    foreach y {csources cflags cc cppflags} {
		set $y [::groups::${x}::flag_read $y]
	    }
	    puts $outfile ": foreach $csources |> ^ CC %f^ $cc $cflags $cppflags -c %f -o %o|> ${x}_%B.o {${x}-objs}"
	}
    }

    proc link {outfile} {
	foreach x $::build::do_targets {
	    if {[::groups::${x}::flag_read linkwith] == "c"} {
		foreach y {cc cflags libs} {
		    set y [::groups::${x}::flag_read $y]
		}
		puts $outfile ": {${x}-objs} |> ^ CCLD %o^ $cc $cflags %f $libs -o %o |> $x"
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

solution libs {libname} {
    puts -nonewline stderr "Testing for $libname with pkg-config...   "
    if {![catch {exec pkg-config --exists $libname}]} {
	puts yes
	solved "libs $libname" [concat "set libname $libname;" {
	    [current]::flag_append cflags [exec pkg-config --cflags $libname]
	    [current]::flag_append libs [exec pkg-config --libs $libname]}]
    } else {
	puts no
    }
    solved "libs $libname" [concat "set libname $libname;" {[current]::flag_append libs -l$libname}]
}

solution ::c::c99 {} {
    puts stderr "Testing for c99...   Making a stupid assumption."
    solved ::c::c99 {[current]::flag_set cc "gcc -std=c99"}
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
