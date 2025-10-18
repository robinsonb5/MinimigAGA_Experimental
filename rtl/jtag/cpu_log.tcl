#!/opt/intelFPGA_lite/18.1/quartus/bin/quartus_stp -t

source [file dirname [info script]]/../../EightThirtyTwo/tcl/vjtagutil.tcl


set CMD_STATUS 0x00
set CMD_GO 0x01
set CMD_READ 0x02
set CMD_RELEASE 0x03
set CMD_SETTRIGGER1 0x04
set CMD_SETTRIGGER2 0x05
set CMD_SETTIME 0x06
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
				vjtag::usbblaster_close
				send_cmd $CMD_STATUS		
				vjtag::usbblaster_open
				set v [vjtag::recv]
			}
			vjtag::usbblaster_close
			set ts [expr $v >> 8]
			puts "timestamp: $ts"
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
				set cpustate [expr $v >> 28]
				set cpuread [expr (($v<<4 & 0xfff0) | ($w>>28))]
				set cpuwrite [expr ($v >> 12) & 0xffff]
				set cpuaddr [expr $w & 0x0fffffff]
				if {$cpustate == 3} {
#					puts $chan "[format %02x [expr $v >> 28]] [format %04x [expr ($v >> 12) & 0xffff]] [format %04x [expr (($v << 4) &0xfff0 ) | ($w >> 28)]] [format %08x [expr $w & 0x0fffffff]]"
					puts $chan "[format %02x $cpustate] [format %04x $cpuwrite] [format %08x $cpuaddr]" 
				} else {				
					puts $chan "[format %02x $cpustate] [format %04x $cpuread] [format %08x $cpuaddr]" 
				}
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
#send_cmd $CMD_SETTRIGGER1 [expr ((0xfff8 << 8) | (2<<3) | 7)]
#send_cmd $CMD_SETTRIGGER2 0x007f

# send_cmd $CMD_SETTRIGGER1 [expr ((0x0e76 << 8) | (0<<3) | 3)]
# send_cmd $CMD_SETTRIGGER2 0x0078

#send_cmd $CMD_SETTRIGGER1 [expr ((0x1a06 << 8) | (0<<3) | 3)]
#send_cmd $CMD_SETTRIGGER2 0x0078

# 5050 OK
# 5100 OK
# 5110 fail
# 6000 fail

# 5105 caught 
# 01 ffff 007b289f
# 00 000a 00781a08
# 00 67f4 00781a0a
#-02 ffff 00400072  <= Maybe to do with using the snoop mechanism for updating the cache with writes?
#+02 00f8 00400072
# 02 48d6 00400074
# 00 206a 00781a0c
# 01 ffff 007bfe6e
# 00 000a 00781a0e
# 00 2241 00781a10
#-02 ffff 00400072
#+02 00f8 00400072
# Fixed by cache tweak

#  5150 OK
# 10000 OK
# 12000 OK
# 12200 OK
# 12400 OK
# 12410 OK / fail
# 12418 OK / fail
# 13000 OK
# 14500 OK
# 15200 OK
# 15700 OK / fail
# 16000 fail
# 20000 fail
# 30000 fail
# 50000 fail

# 10000 OK
# 15000 OK
# 16000 OK
# 18000 fail
# 20000 fail

send_cmd $CMD_SETTIME [expr 17000 << 8]
send_cmd $CMD_SETTRIGGER1 4
#
#send_cmd $CMD_SETTRIGGER1 [expr ((0x1a06 << 8) | (0<<3) | 4)]
#send_cmd $CMD_SETTRIGGER2 0x0078

set chan [open "dump.txt" w]

for {set i 0} {$i < 2} {incr i} {
	puts $i
	send_cmd $CMD_GO
	wait_fifo
	send_cmd $CMD_READ
	dump_fifo $chan
}
# send_cmd $CMD_RELEASE

close $chan

##################### End Code ########################################

