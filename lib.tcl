namespace eval groups {}
namespace eval build_helpers {
    namespace export *
    array set solvers {}
    
    proc solve {args} {
	global solvers
	puts -nonewline stderr "Testing for $args...\t"
	for {set i [expr {[llength $args]-1}]} {$i >= 0} {incr i -1} {
	    if {[info exists solvers([lrange $args 0 $i])]} {
		foreach x $solvers([lrange $args 0 $i]) {
		    if {[uplevel $x [lrange $args [expr {$i+1}] end]]} {
			return
		    }
		}
	    }
	}
	puts stderr "Could not find solver for $args."
	exit 1
    }
    
    proc solution {solver name arg commands} {
	global solvers
	uplevel [list proc $name $arg $commands]
	lappend solvers($solver)
	set solvers($solver) [linsert $solvers($solver) 0 [uplevel namespace which $name]]
    }
    
    proc solved {name commands} {
	global solvers
	uplevel $commands
	set solvers($name) [list apply [list {} $commands]]
	uplevel "return 1"
    }
    
    proc solvewith {solver name} {
	uplevel "proc $name {args} {uplevel ::build_helpers::solve $solver \{*\}\$args}"
	uplevel namespace export $name
    }
    
    proc solvewith_map {solver name} {
	uplevel "proc $name {args} {foreach x \$args {uplevel ::build_helpers::solve $solver \$x}}"
	uplevel namespace export $name
    }
    
    proc current {} {
	return [uplevel 2 namespace current]
    }
}
namespace eval build {
    namespace export program module in-directory uses c targets option enable main
    namespace import ::build_helpers::*

    proc gen_space {name type commands} {
	lappend ::build::groups $name
	namespace eval ::groups::$name set type $type
	namespace eval ::groups::$name {
	    set working_dir ..
	    proc flag_set {flag val} {
		variable $flag
		set $flag $val
	    }
	    proc flag_read {flag} {
		variable $flag
		if {![info exists $flag]} {
		    return ""
		} else {
		    return [set $flag]
		}
	    }
	    proc flag_append {flag val} {
		variable $flag
		lappend $flag $val
	    }
	}
	proc ::groups::${name}::do {} $commands
    }
    
    proc program {name commands} {
	lappend ::build::possible_targets $name
	gen_space $name program $commands
    }
    
    proc module {name commands} {
	gen_space $name module $commands
    }

    proc in-directory {dir args} {
	if {$args == {}} {
	    append [current]::working_dir "/$dir"
	} else {
	    set tmp [set [current]::working_dir]
	    append [current]::working_dir $dir
	    uplevel $args
	    set [current]::working_dir $tmp
	}
    }

    proc uses {args} {
	foreach x $args {
	    uplevel ::groups::${x}::do
	}
    }

    namespace eval c {
	namespace export define libs test needs sources
	namespace import ::build_helpers::*

	proc define {args} {
	    foreach x $args {
		[current]::flag_append cppflags -D$x
	    }
	}
	
	namespace eval needs {
	    namespace import ::build_helpers::*
	    solvewith c99 c99
	    solvewith_map libs libs
	    namespace ensemble create
	}
	
	proc sources {args} {
	    if {[[current]::flag_read type] != "modules" && ![info exists [current]::linkwith]} {
		[current]::flag_set linkwith c
	    }
	    foreach x $args {
		[current]::flag_append csources [[current]::flag_read working_dir]/$x
	    }
	}

	proc generate {outfile} {
	    foreach x $::build::groups {
		if {[::build::enable get $x] && [::groups::${x}::flag_read csources] != ""} {
		    foreach y {csources cflags cc cppflags} {
			set $y [::groups::${x}::flag_read $y]
		    }
		    puts $outfile ": foreach $csources |> ^ CC %f^ $cc $cflags $cppflags -c %f -o %o|> ${x}_%B.o {${x}-objs}"
		}
	    }
	}
	
	proc link {outfile} {
	    foreach x $::build::groups {
		if {[::build::enable get $x]} {
		    if {[::groups::${x}::flag_read linkwith] == "c"} {
			foreach y {cc cflags libs} {
			    set $y [::groups::${x}::flag_read $y]
			}
			puts $outfile ": {${x}-objs} |> ^ CCLD %o^ $cc $cflags %f $libs -o %o |> $x"
		    }
		}
	    }
	}

	namespace ensemble create
    }

    namespace eval targets {
	namespace export are default
	proc are {args} {
	    foreach x $args {
		::build::enable add $x
		lappend ::build::targets $x
	    }
	}

	proc default {args} {
	    foreach x $args {
		::build::enable default $x
	    }
	}
	namespace ensemble create
    }

    namespace eval enable {
	namespace export add get default
	proc add {x} {
	    set ::build::enable($x) 0
	}
	proc get {x} {
	    return [set ::build::enable($x)]
	}
	proc default {x} {
	    if {[info exists ::build::enable($x)]} {
		set ::build::enable($x) 1
	    } else {
		error "No such enable argument $x."
	    }
	}
	namespace ensemble create
    }

    namespace eval option {
	namespace export add get default
	proc add {name args} {
	    set ::build::options($name) {}
	    if {[llength $args] != 0} {
		set ::build::options_args($name) $args
	    }
	}
	proc get {name} {
	    return [set ::build::options($name)]
	}
	proc default {name x} {
	    set ::build::options($name) $x
	}
    }

    namespace eval invalid_arg {
	namespace export enable disable choice option
	proc enable {arg} {
	    puts stderr "Invalid argument --enable-$arg."
	    puts stderr "Choices are: "
	    foreach x [array get ::build::enable] {
		puts stderr "\t--enable-[lindex $x 0]"
	    }
	    exit 1
	}

	proc disable {arg} {
	    puts stderr "Invalid argument --disable-$arg."
	    puts stderr "Choices are:"
	    foreach x [array names ::build::enable] {
		puts stderr "\t--disable-$x"
	    }
	    exit 1
	}

	proc choices {arg setting} {
	    puts stderr "Invalid setting for argument --$arg."
	    puts stderr "Choices are:"
	    foreach x [array names ::build::options_args] {
		puts stderr "\t--$arg=$x"
	    }
	    exit 1
	}

	proc option {arg} {
	    puts stderr "Invalid argument $arg."
	    puts stderr "Choices are:"
	    foreach x [array names ::build::options] {
		if {[info exists ::build::options_args($x)]} {
		    puts stderr "\t--${x}=[join $::build::options_args($x) {, }]"
		} else {
		    puts stderr "\t--$x"
		}
	    }
	    foreach x [array names ::build::enable] {
		puts stderr "\t--enable-$x --disable-$x"
	    }
	    exit 1
	}
	namespace ensemble create
    }

    proc main {argv} {
	if {![info exists ::build::targets]} {
	    if {![info exists ::build::possible_targets]} {
		return 0
	    }
	    targets are {*}$::build::possible_targets
	    targets default {*}$::build::possible_targets
	}
	foreach x $argv {
	    switch -regexp -matchvar matches -- $x {
		{--enable-(.*)} {
		    if {[info exists ::build::enable([lindex $matches 1])]} {
			set ::build::enable([lindex $matches 1]) 1
		    } else {
			invalid_arg enable [lindex $matches 1]
		    }
		}
		{--disable-(.*)} {
		    if {[info exists ::build::enable([lindex $matches 1])]} {
			set ::build::enable([lindex $matches 1]) 0
		    } else {
			invalid_arg disable [lindex $matches 1]
		    }
		}
		{--([^=]*)=(.*)} {
		    if {[info exists ::build::options([lindex $matches 1])]} {
			if {[info exists ::build::options_args([lindex $matches 1])]} {
			    if {[lsearch $::build::options_args([lindex $matches 1]) [lindex $matches 3]]} {
				set ::build::options([lindex $matches 1]) [lindex $matches 3]
			    } else {
				invalid_arg choice [lindex $matches 1] [lindex $matches 3]
			    }
			} else {
			    set ::build::options([lindex $matches 1]) [lindex $matches 3]
			}
		    } else {
			invalid_arg option "--[lindex $matches 1]"
		    }
		}
		default {
		    invalid_arg option $x
		}
	    }
	}

	set outfile [open objs/Tupfile w]
	foreach x $::build::targets {
	    if {[enable get $x]} {
		::groups::${x}::do
	    }
	}
	::build::c::generate $outfile
	::build::c::link $outfile
	close $outfile
    }
}

source tests.tcl

namespace import ::build::*
