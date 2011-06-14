namespace eval tests {
    namespace eval c {
	namespace import ::build_helpers::*

	proc testbuild {cc cflags libs source} {
	    set file [open tmp.c "w"]
	    puts $file $source
	    close $file
	    set ret 1
	    if {![catch {exec $cc $cflags tmp.c $libs}]} {
		set ret 0
	    } else {
		if {![catch {exec ./a.out}]} {
		    set ret 0
		}
	    }
	    file delete a.out tmp.c
	    return $ret
	}

	proc generate_csource {headers prelude main} {
	    return [concat $headers "\n" $prelude "\n" "int main() {\n" $main "}\n"]
	}

	proc generate_define_test {headers prelude test} {
	    generate_csource $headers $prelude "#if $test\nreturn 0;\n#else\nreturn 1;\n#endif"
	}

	proc test_stdcversion99 {cc} {
	    testbuild $cc {} {} [generate_define_test {} {} "defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L"]
	}

	proc c99_compile_solution {name cc} {
	    uplevel [list solution c99 c99_${name}_std {} [concat "set cc \"$cc -std=c99\";" {
		if {[testbuild $cc {} {} [generate_define_test {} {} "defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L"]]} {
		    puts "yes; $cc -std=c99"
		    solved c99 "\[current\]::flag_set cc [list $cc]"
		}
	    }]]
	    uplevel [list solution c99 c99_$name {} [concat "set cc $cc;" {
		if {[testbuild $cc {} {} [generate_define_test {} {} "defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L"]]} {
		    puts "yes; $cc"
		    solved c99 "\[current\]::flag_set cc [list $cc]"
		}
	    }]]
	}

	foreach x {c99 cc clang gcc} {
	    c99_compile_solution $x $x
	}
	c99_compile_solution env $::env(CC)

	solution libs libs_try_link {libname} {
	    if {[testbuild [[current]::flag_read cc] {} -l$libname {return 0;}]} {
		puts "yes; -l$libname"
		solved "libs $libname" [concat "set libname $libname;" {[current]::flag_append libs -l$libname}]
		return 1
	    }
	    return 0
	}

	solution libs libs_pkgconfig {libname} {
	    if {![catch {exec pkg-config --exists $libname}]} {
		puts "yes; `pkg-config --libs $libname`"
		solved "libs $libname" [concat "set libname $libname;" {
		    [current]::flag_append cflags [exec pkg-config --cflags $libname]
		    [current]::flag_append libs [exec pkg-config --libs $libname]}]
		return 1
	    }
	    return 0
	}
    }
}
