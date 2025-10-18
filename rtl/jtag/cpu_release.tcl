#!/opt/intelFPGA_lite/18.1/quartus/bin/quartus_stp -t

source [file dirname [info script]]/../../EightThirtyTwo/tcl/vjtagutil.tcl


set CMD_STATUS 0x00
set CMD_GO 0x01
set CMD_READ 0x02
set CMD_RELEASE 0x03
set CMD_SETTRIGGER1 0x04
set CMD_SETTRIGGER2 0x05
set CMD_RESET 0xff

####################### Main code ###################################


proc send_cmd {cmd {data 0}} {
	global connected
	set contmp $connected;
	set connected 0
	if {$contmp} {
		if [ vjtag::usbblaster_open ] {
			vjtag::send [expr (($cmd << 24) | $data) ]
		}
		vjtag::usbblaster_close
	}
	set connected $contmp
}

proc get_word {} {
	global connected
	set contmp $connected;
	set connected 0
	if {$contmp} {
		if [ vjtag::usbblaster_open ] {
			set word [vjtag::recv]
		}
		vjtag::usbblaster_close
	}
	set connected $contmp
	return $word
}

proc reset {} {
	global CMD_RESET
	send_cmd $CMD_RESET
}

proc release {} {
	global CMD_RELEASE
	send_cmd $CMD_RELEASE
}


proc connect {} {
	global connected
	set connected 0

	if { [vjtag::select_instance 0xc106] < 0} {
		puts "Connection failed\n"
		set connected 0
	} else {
		puts "Connected to:\n$::vjtag::usbblaster_name\n$::vjtag::usbblaster_device"
		set connected 1
	}
}


proc drain_fifo {} {
	global connected
	if {$connected} {
		if [ vjtag::usbblaster_open ] {
			while {[vjtag::recv] >-1 } {
			}
			vjtag::usbblaster_close
		}
	}
}


proc wait_fifo {} {
	global CMD_STATUS
	global connected
	if {$connected} {
		send_cmd $CMD_STATUS		
		if [ vjtag::usbblaster_open ] {
			set v [vjtag::recv]
			while {($v & 1) == 0} {
				set v [vjtag::recv]
			}
			vjtag::usbblaster_close
		}
	}
}

proc dump_fifo {chan} {
	global connected
	if {$connected} {
	
		if [ vjtag::usbblaster_open ] {
			set w [vjtag::recv]
			set v [vjtag::recv]
			while {$v >-1 } {
				puts $chan "[format %02x [expr $v >> 28]] [format %04x [expr ($v >> 12) & 0xf]] [format %04x [expr (($v << 4) &0xfff0 ) | ($w >> 28)]] [format %08x [expr $w & 0x0fffffff]]"
				set w [vjtag::recv]
				set v [vjtag::recv]
			}
			vjtag::usbblaster_close
		}
	}
}


proc send_fetch {} {
	global CMD_FETCH

	drain_fifo
	send_cmd $CMD_REPORT

	if {$connected} {
		if [ vjtag::usbblaster_open ] {
			set v1 [vjtag::recv_blocking]
			set v2 [vjtag::recv_blocking]
			puts $v1 $v2
		}
		vjtag::usbblaster_close
	}
}

##################### EXAMPLE USAGE ###################################

connect

send_cmd $CMD_RELEASE

##################### End Code ########################################

