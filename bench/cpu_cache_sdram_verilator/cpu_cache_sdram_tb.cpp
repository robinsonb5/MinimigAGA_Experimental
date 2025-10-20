#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <list>
#include "Vcpu_cache_sdram_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"


static Vcpu_cache_sdram_tb *tb;
static VerilatedVcdC *trace;
static double timestamp = 0;

double sc_time_stamp() {
	return timestamp;
}

void tick(int c) {
	tb->clk_114 = c;
	tb->eval();
	trace->dump(timestamp);
	timestamp += 4.38;
}


void cpuInternalCycle()
{
	static int counter=0;
	counter=(counter+1)&7;
	if(!counter)
	{
		tb->cpuL = 1;
		tb->cpuU = 1;
		tb->cpuState = 1;
		tick(1);
		tick(0);
		tb->cpuWR = 0xdead;
		tb->cpuAddr = rand() & 0x3ffffff;
		do {
			tick(1);
			tick(0);
		} while (!tb->clkena);
	}
}


void cpuWrite(int addr, int data,int udqm=0,int ldqm=0)
{
	cpuInternalCycle();
	tb->cpuL = ldqm;
	tb->cpuU = udqm;
	tb->cpuState = 3;	/* State is freshly registered, so should be available at the next clock */
	tick(1);
	tick(0);
	tb->cpuAddr = addr>>1;  /* Addr takes a couple of cycles to settle */
	tb->cpuWR = data;
	do {
		tick(1);
		tick(0);
	} while (!tb->clkena);
}


void cpuWriteL(int addr, int data)
{
	tb->cpuLongWord=1;
	cpuWrite(addr,data>>16);
	tb->cpuLongWord=0;
	cpuWrite(addr+2,data);
}


int cpuRead(int addr, char d)
{
	cpuInternalCycle();
	tb->cpuL = 0;
	tb->cpuU = 0;
	tb->cpuState = d ? 2 : 0;
	tick(1);
	tick(0);
	tb->cpuAddr = addr>>1;
	do {
		tick(1);
		tick(0);
	} while (!tb->clkena);
	return tb->cpuRD;
}


bool cpuVerify(int addr, char d,const char *label="",int expectvalue=-1)
{
	bool result=true;
	int v=cpuRead(addr,d);
	if(v!=expectvalue) {
		std::cout << "time: " << timestamp << " - error at addr: " << addr << " " << label << " : " << std::hex << tb->cpuRD << ", expected " << expectvalue << std::dec << std::endl;
		result=false;
	}
	return result;
}


void expungeL1(int addr,char d)
{
	cpuRead(addr+32,d);
	cpuRead(addr+64,d);
}


void expungeL2(int addr,char d)
{
	for(int i=0;i<4;++i)
		cpuRead(addr+16384*i,d);
}


void preloadL2(int addr,char d)
{
	cpuRead(addr,d);
	expungeL1(addr,d);
}


char basic_test() {
	char ok = 1;
	for (int i=0; i<32;i++) {
		cpuWrite(i*2,rand());
		int dat = cpuRead(i*2,1);
	}
	for (int i=0; i<17;i++) {
		cpuWrite(i*2,i);
		cpuRead(0x2220+i,0);
		ok&=cpuVerify(i*2,1,"",i);
	}
	return ok;
}

char byte_test() {
	char ok = 1;
	for (int i=0; i<16;i++) {
		preloadL2(i*4,0);
		int t=(i*0x1221) & 0xffff;
		int t2=(i*0x2332) & 0xffff;
		cpuWrite(i*4,t,1,0);
		cpuWrite(i*4,t2,0,1);
		int dat;
		t=(t&0xff) | (t2 & 0xff00);

		ok&=cpuVerify(i*4,1,"(d1)",t);

		expungeL1(i*4,1);
		ok&=cpuVerify(i*4,1,"(d2)",t);
		dat = cpuRead(i*4,1);

		expungeL2(i*4,1);
		ok&=cpuVerify(i*4,1,"(d3)",t);
		ok&=cpuVerify(i*4,0,"(i1)",t);
	}
	return ok;
}

char long_write_test(int adr) {
	char ok = true;
	preloadL2(adr,0);
	preloadL2(adr,1);
	cpuWriteL(adr,0x12345678);
	
	ok &= cpuVerify(adr  ,1,"(d)",0x1234);
	ok &= cpuVerify(adr+2,1,"(d)",0x5678);
	ok &= cpuVerify(adr  ,0,"(i)",0x1234);
	ok &= cpuVerify(adr+2,1,"(i)",0x5678);

	expungeL2(adr,0);
	expungeL2(adr,1);

	ok &= cpuVerify(adr  ,1,"(d2)",0x1234);
	ok &= cpuVerify(adr+2,1,"(d2)",0x5678);
	ok &= cpuVerify(adr  ,0,"(i2)",0x1234);
	ok &= cpuVerify(adr+2,1,"(i2)",0x5678);

	return(ok);	
}

char random_test(int iterations) {
	int counter;
	int okcounter=0;
	char ok = 1;
	std::list<int> addresses;
	std::cout << "memory random fill" << std::endl;
	for (int i=0; i<iterations; i++)
	{
		int a = rand() & 0xfffffc;
		addresses.push_back(a);
		cpuWrite(a,a & 0xffff);
	}

	std::cout << "memory read back after random fill" << std::endl;
	for (std::list<int>::iterator it=addresses.begin(); it != addresses.end(); ++it)
	{
		int a=*it;
		int d=a & 0xffff;
		int data = cpuRead(a, counter>5 ? 1 : 0);
		counter=(counter+1)%9;
		if ((*it & 0xffff) != data) {
			std::cout << "time: " << timestamp << " - error: " << okcounter << " good reads, then " << std::setw(8) << std::setfill('0') << std::hex << a << ": " << data << ", expected " << d << std::dec << std::endl;
			ok = 0;
			okcounter=0;
		}
		else
			++okcounter;
	}
	return ok;
}

char consecutive_test(int iterations) {
	int counter;
	int okcounter=0;
	char ok = 1;
	std::list<int> addresses;
	std::cout << "memory consecutive fill" << std::endl;
	for (int j=0; j<(iterations/32); ++ j)
	{
		int a = rand() & 0xfffffc;
		for (int i=0; i<32; i++)
		{
			addresses.push_back(a+i*2);
			cpuWrite(a+i*2,(a+i*2) & 0xffff);
		}
	}

	std::cout << "memory read back after consecutive fill" << std::endl;
	for (std::list<int>::iterator it=addresses.begin(); it != addresses.end(); ++it)
	{
		int a=*it;
		int d=a & 0xffff;
		int data = cpuRead(a, counter>5 ? 1 : 0);
		counter=(counter+1)%9;
		if ((*it & 0xffff) != data) {
			std::cout << "time: " << timestamp << " - error: " << okcounter << " good reads, then " << std::setw(8) << std::setfill('0') << std::hex << a << ": " << data << ", expected " << d << std::dec << std::endl;
			ok = 0;
			okcounter=0;
		}
		else
			++okcounter;
	}
	return ok;
}


char prefetch_test(int iterations) {
	int addr;
	int counter=0;
	int okcounter=0;
	char ok = 1;
	std::list<int> data;
	std::cout << "memory prefetch fill" << std::endl;
	for (int j=0; j<iterations; ++ j) {
		int d = rand() & 0xffff;
		addr = j*2;
		data.push_back(d);
		cpuWrite(addr,d);
	}

	std::cout << "Time : " << timestamp << " - memory read back after fill" << std::endl;
	addr=0;
	for (std::list<int>::iterator it=data.begin(); it != data.end(); ++it)
	{
		int d=*it;
		if((counter%5)==0)
			tb->newpc=1;
		else
			tb->newpc=0;
		++counter;

		if(counter==7)
			cpuWrite(0x3022,0xdead);
		if(counter==10)
			cpuWriteL(0x3024,0xbeefc0de);

		if(cpuVerify(addr,0,"",d))
			++okcounter;		
		else {
			std::cout << okcounter << " good reads" << std::endl;
			ok = 0;
			okcounter=0;
		}
		addr+=2;
	}
	ok &= cpuVerify(0x3022,1,"(d)",0xdead);
	ok &= cpuVerify(0x3024,1,"(d)",0xbeef);
	ok &= cpuVerify(0x3026,1,"(d)",0xc0de);
	ok &= cpuVerify(0x3022,0,"(d)",0xdead);
	ok &= cpuVerify(0x3024,0,"(d)",0xbeef);
	ok &= cpuVerify(0x3026,0,"(d)",0xc0de);
	std::cout << "Time : " << timestamp << " done" << std::endl;
	tb->newpc=1;
	return ok;
}


char btbtest(int iterations) {
	int addr;
	int counter=0;
	int okcounter=0;
	char ok = 1;
	std::vector<int> data;
	std::cout << "BTB pre-fill" << std::endl;
	for (int j=0; j<iterations*2; ++ j) {
		int d = rand() & 0xffff;
		addr = j*2;
		data.push_back(d);
		cpuWrite(addr,d);
	}

	for(int k=0;k<2;++k) {
		std::cout << "Time : " << timestamp << " - memory read back after fill" << std::endl;
		addr=0;
		tb->newpc=0;
		for (int i=0;i<iterations/4;++i) {
			for (int j=0;j<iterations/4;++j) {
				if(j<((iterations/4)-1))
					tb->newpc=0;
				else
					tb->newpc=1;
				addr=(i*(iterations/8) + j)*2;
	//			std::cout << addr << std::endl;
				int d=data[addr/2];
				ok &= cpuVerify(addr,0,"",d);
			}
		}
	}
	tb->newpc=1;
	return ok;
}


char l1filltest()
{
	char ok=1;
	expungeL2(0,1);
	expungeL2(0,0);
	for(int i=0;i<16;++i)
		cpuWrite(i*2,i*0x0101);
	cpuRead(0,1);
	expungeL1(0,1);
	cpuRead(0,1);
	tb->cpuL = 1;
	tb->cpuU = 1;
	tb->cpuState = 1;
	tb->cpuWR = 0xdead;
	tb->cpuAddr = 0x8010;
	for(int i=1;i<=8;++i)
		tick(i&1);
	for(int i=0;i<8;++i)
	{
		ok&=cpuVerify(i*2,1,"",i*0x0101);
	}	
	return(ok);
}


char random_test_128meg(int iterations=50) {
	char ok = 1;
	int offset=64*1024*1024;
	std::list<int> addresses;
	std::cout << "memory random fill" << std::endl;
	for (int i=0; i<iterations; i++)
	{
		int a = rand() & 0xfffffc;
		addresses.push_back(a);
		cpuWrite(a,a & 0xffff);
		cpuWrite(a+offset,0xffff ^ (a & 0xffff));
	}

	std::cout << "memory read back after random fill" << std::endl;
	for (std::list<int>::iterator it=addresses.begin(); it != addresses.end(); ++it)
	{
		int a=*it;
		int d=a & 0xffff;
		int data = cpuRead(a, 1);
		int data2 = cpuRead(a+offset, 1);
		if (d != data) {
			std::cout << "error: " << std::setw(8) << std::setfill('0') << std::hex << a << ": " << data << ", expected " << d << std::dec << std::endl;
			ok = 0;
		}
		if ((d^0xffff) != data2) {
			std::cout << "error: " << std::setw(8) << std::setfill('0') << std::hex << a+offset << ": " << data2 << ", expected " << (d^0xffff) << std::dec << std::endl;
			ok = 0;
		}
	}
	return ok;
}


void runtests(int tests) {
	if(tests&1) {
		if (basic_test())
			std::cout << " - Basic test: OK" << std::endl;
		else
			std::cout << " - Basic test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (prefetch_test(16))
			std::cout << " - Prefetch test: OK" << std::endl;
		else
			std::cout << " - Prefetch test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (byte_test())
			std::cout << " - Byte test: OK" << std::endl;
		else
			std::cout << " - Byte test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (long_write_test(16))
			std::cout << " - Aligned long write: OK" << std::endl;
		else
			std::cout << " - Aligned long write: ERROR" << std::endl;
		if (long_write_test(22))
			std::cout << " - Unaligned long write: OK" << std::endl;
		else
			std::cout << " - Unaligned long write: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (random_test(1000))
			std::cout << " - Random test: OK" << std::endl;
		else
			std::cout << " - Random test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (consecutive_test(1000))
			std::cout << " - Consecutive test: OK" << std::endl;
		else
			std::cout << " - Consecutive test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (l1filltest())
			std::cout << " - Level 1 fill test: OK" << std::endl;
		else
			std::cout << " - Level 1 fill test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (btbtest(32))
			std::cout << " - BTB test: OK" << std::endl;
		else
			std::cout << " - BTB test: ERROR" << std::endl;
	}
	tests>>=1;
	if(tests&1) {
		if (random_test_128meg(50))
			std::cout << "Random test 128meg: OK" << std::endl;
		else
			std::cout << "Random test 128meg: ERROR" << std::endl;
	}
}


int main(int argc, char **argv) {

	// Initialize Verilators variables
	Verilated::commandArgs(argc, argv);
//	Verilated::debug(1);
	Verilated::traceEverOn(true);
	trace = new VerilatedVcdC;

	// Create an instance of our module under test
	tb = new Vcpu_cache_sdram_tb;
	tb->trace(trace, 99);
	trace->open("sdram.vcd");

	tb->reset = 0;
	tb->cpuL = 0;
	tb->cpuU = 0;
	tb->cpuLongWord = 0;
	tb->cpuState = 1;
	tb->cpuWR = 0xdead;
	tb->cpuAddr = 0;
	tb->newpc=1;
	tick(1);
	tick(0);
	tick(1);
	tick(0);
	tb->reset = 1;
	tick(1);
	tick(0);

	while(!tb->reset_out) {
		tick(1);
		tick(0);	
	}

	cpuRead(0,0); // Dummy op to wait for SDRAM to be ready
//	cpuWrite(17,0xDEAD);
//	cpuRead(17,0); // Dummy op to wait for SDRAM to be ready
	cpuWrite(4,0xDEAD);

//	tb->cache_ctrl=0;

//	std::cout << "**** Running tests with cache disabled" << std::endl;
//	runtests();

	tb->cache_ctrl=1;

	std::cout << "**** Running tests with cache enabled" << std::endl;
	int tests=-1;
	if(argc>1)
		tests = atoi(argv[1]);
	runtests(tests);

	trace->close();

}
