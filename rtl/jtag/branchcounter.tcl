#!/opt/intelFPGA_lite/18.1/quartus/bin/quartus_stp -t

#   jtagbridge.tcl - Virtual JTAG proxy for Altera devices

package require Tk
init_tk

source [file dirname [info script]]/../../EightThirtyTwo/tcl/vjtagutil.tcl

set CMD_STOP 0x00
set CMD_START 0x01
set CMD_FETCH 0x02
set CMD_GETCOUNT 0x03
set CMD_RESET 0xff

set branchcount 0
set branchramcount 0
set contcount 0
set contramcount 0
set newpcfaultcount 0
set totalcount 0

####################### Main code ###################################

proc updatedisplay {} {
	global CMD_GETCOUNT
	global connected
	global totalcount
	send_cmd $CMD_GETCOUNT 
	if {$connected} {
		if [ vjtag::usbblaster_open ] {
			set totalcount [vjtag::recv_blocking ]
		}
		vjtag::usbblaster_close
	}
	after 50 updatedisplay
}



proc send_cmd {cmd} {
	global connected
	set contmp $connected;
	set connected 0
	if {$contmp} {
		if [ vjtag::usbblaster_open ] {
			vjtag::send [expr ($cmd << 24) ]
		}
		vjtag::usbblaster_close
	}
	set connected $contmp
}


proc connect {} {
	global displayConnect
	global connected
	set connected 0

	if { [vjtag::select_instance 0xbc68] < 0} {
		set displayConnect "Connection failed\n"
		set connected 0
	} else {
		set displayConnect "Connected to:\n$::vjtag::usbblaster_name\n$::vjtag::usbblaster_device"
		set connected 1
	}
}


proc send_stop {} {
	global CMD_STOP
	send_cmd $CMD_STOP
}

proc send_start {} {
	global CMD_START
	global connected
	global branchcount 
	global branchramcount
	global contcount
	global contramcount
	global totalcount 
	global newpcfaultcount

	set contcount 0
	set contramcount 0
	set branchcount 0
	set branchramcount 0
	set newpcfaultcount 0
	set totalcount 0

	send_reset
	send_cmd $CMD_START
}

proc send_reset {} {
	global CMD_RESET
	send_cmd $CMD_RESET
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


proc send_fetch {} {
	global CMD_STOP
	global CMD_FETCH
	global connected
	global branchcount
	global branchramcount
	global contcount
	global contramcount
	global totalcount 
	global newpcfaultcount
	

	drain_fifo
	send_cmd $CMD_FETCH
	send_cmd $CMD_STOP

	if {$connected} {
		if [ vjtag::usbblaster_open ] {
			set totalcount [vjtag::recv_blocking]
			set contcount [vjtag::recv_blocking]
			set contramcount [vjtag::recv_blocking]
			set branchcount [vjtag::recv_blocking]
			set branchramcount [vjtag::recv_blocking]
			set newpcfaultcount [vjtag::recv_blocking]
		}
		vjtag::usbblaster_close
	}

	global contpercent
	global contrampercent
	global branchpercent 
	global branchrampercent 
	set contpercent "[expr $contcount * 100 / $totalcount]%"
	set contrampercent "[expr $contramcount * 100 / $totalcount]%"
	set branchpercent "[expr $branchcount * 100 / $totalcount]%"
	set branchrampercent "[expr $branchramcount * 100 / $totalcount]%"

#	send_cmd $CMD_FETCH
#	send_cmd $CMD_STOP
}



wm state . normal
wm title . "CPU Branch Analyzer"

global connected
set connected 0

frame .frmConnection -relief sunken -borderwidth 2 -padx 5 -pady 5
pack .frmConnection -fill both -expand 1

set  displayConnect "Not yet connected\nNo Interface\nNo Device"
label .lblConn -justify left -textvariable displayConnect
button .btnConn -text "Connect..." -command "connect"
button .btnReset -text "Reset" -command "send_reset"

grid .btnConn -in .frmConnection -row 0 -column 0 -padx 5 -sticky ew
grid .btnReset -in .frmConnection -row 1 -column 0 -padx 5 -sticky ew
grid .lblConn -in .frmConnection -row 0 -column 1 -rowspan 2 -padx 5 -pady 5

frame .frame -relief sunken -borderwidth 2 -padx 5 -pady 5
pack .frame -fill both -expand yes

button .btnStart -text "Start" -command send_start
button .btnFetch -text "Stop" -command send_fetch


set branchcount 0
set branchpercent 0
set branchramcount 0
set branchrampercent 0
set contcount 0
set contpercent 0
set contramcount 0
set contrampercent 0
set newpcfaultcount 0
set totalcount 0

label .contlabel -text "Continuous Fetch"
grid .contlabel -in .frame -row 0 -column 0 -padx 5 -pady 5 -sticky ew
label .contdisp -textvariable contcount
grid .contdisp -in .frame -row 0 -column 1 -padx 5 -pady 5 -sticky w
label .contpercentdisp -textvariable contpercent
grid .contpercentdisp -in .frame -row 0 -column 2 -padx 5 -pady 5 -sticky w

label .readlabel -text "Continous RAM Fetch"
grid .readlabel -in .frame -row 1 -column 0 -padx 5 -pady 5 -sticky ew
label .contramdisp -textvariable contramcount
grid .contramdisp -in .frame -row 1 -column 1 -padx 5 -pady 5 -sticky w
label .contrampercentdisp -textvariable contrampercent
grid .contrampercentdisp -in .frame -row 1 -column 2 -padx 5 -pady 5 -sticky w

label .branchlabel -text "Branch Fetch"
grid .branchlabel -in .frame -row 2 -column 0 -padx 5 -pady 5 -sticky ew
label .branchdisp -textvariable branchcount
grid .branchdisp -in .frame -row 2 -column 1 -padx 5 -pady 5 -sticky w
label .branchpercentdisp -textvariable branchpercent
grid .branchpercentdisp -in .frame -row 2 -column 2 -padx 5 -pady 5 -sticky w

label .branchramlabel -text "Branch RAM Fetch"
grid .branchramlabel -in .frame -row 3 -column 0 -padx 5 -pady 5 -sticky ew
label .branchramdisp -textvariable branchramcount
grid .branchramdisp -in .frame -row 3 -column 1 -padx 5 -pady 5 -sticky w
label .branchrampercentdisp -textvariable branchrampercent
grid .branchrampercentdisp -in .frame -row 3 -column 2 -padx 5 -pady 5 -sticky w

label .newpcfaultlabel -text "Newpc faults"
grid .newpcfaultlabel -in .frame -row 4 -column 0 -padx 5 -pady 5 -sticky ew
label .newpcfaultdisp -textvariable newpcfaultcount
grid .newpcfaultdisp -in .frame -row 4 -column 1 -padx 5 -pady 5 -sticky w

label .writelabel -text "Total Cycles"
grid .writelabel -in .frame -row 5 -column 0 -padx 5 -pady 5 -sticky ew
label .totaldisp -textvariable totalcount
grid .totaldisp -in .frame -row 5 -column 1 -padx 5 -pady 5 -sticky w

grid .btnStart -in .frame -row 6 -column 0 -padx 5 -pady 2 -sticky ew
grid .btnFetch -in .frame -row 6 -column 1 -padx 5 -pady 2 -sticky ew

update

connect
updatedisplay
tkwait window .


##################### End Code ########################################

