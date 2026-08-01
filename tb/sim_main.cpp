#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtb_top.h"

int main(int argc, char** argv) {
    // Initialize Verilator parameters
    Verilated::commandArgs(argc, argv);
    
    // Turn on design tracing infrastructure
    Verilated::traceEverOn(true);
    
    // Instantiate our top testbench simulation model wrapper
    Vtb_top* top = new Vtb_top;
    
    // Instantiate the standard VCD wave logger container
    VerilatedVcdC* m_trace = new VerilatedVcdC;
    top->trace(m_trace, 99); // Trace up to 99 design hierarchy layers deep
    m_trace->open("waveform.vcd");
    
    // Execute simulation loop until the SystemVerilog testbench finishes ($finish)
    while (!Verilated::gotFinish()) {
        // Advance the evaluation tick step
        top->eval();
        
        // Log all wire states into our trace container at the current time tick
        m_trace->dump(Verilated::time());
        
        // Contextually advance the internal simulation engine timeline state
        Verilated::timeInc(1);
    }
    
    // Clean up objects and safely flush trace buffers out to disk
    m_trace->close();
    top->final();
    
    delete top;
    delete m_trace;
    return 0;
}
