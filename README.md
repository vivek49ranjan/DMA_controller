<h1>Scatter-Gather DMA Controller</h1>

<p>A high-performance Scatter-Gather Direct Memory Access (DMA) controller implemented in Verilog. This core utilizes the AMBA AXI protocol to autonomously transfer data between memory-mapped peripherals and standard memory without continuous CPU intervention.</p>

<p>The controller leverages a linked-list descriptor fetching mechanism, allowing it to execute complex, non-contiguous memory transfers (scatter-gather) and features a built-in AXI router to map transactions across multiple memory and I/O slave devices.</p>

<hr>

<h2>Key Features</h2>

<ul>
    <li><strong>Scatter-Gather Operation:</strong> Fetches transfer descriptors autonomously from memory via a linked-list structure.</li>
    <li><strong>Standard AXI Interfaces:</strong>
        <ul>
            <li><strong>AXI Master:</strong> Handles high-throughput data transfers and descriptor fetching.</li>
            <li><strong>AXI-Lite Slave:</strong> Provides a lightweight interface for CPU configuration and control.</li>
        </ul>
    </li>
    <li><strong>Integrated AXI Router:</strong> Routes transactions between the DMA Master and specific address spaces:
        <ul>
            <li><code>0x0000_0000</code>: Main Memory (Internal SRAM)</li>
            <li><code>0x4X00_0000</code>: 8 independent I/O Slaves</li>
        </ul>
    </li>
    <li><strong>Robust Error Handling:</strong> Detects and reports AXI Slave Errors (SLVERR), Decode Errors (DECERR), and Descriptor Ownership Errors directly back to the status word.</li>
    <li><strong>Asynchronous Support Readiness:</strong> Internal operations are buffered using a built-in synchronous FIFO, architected to allow easy decoupling into asynchronous clock domains if needed.</li>
</ul>

<hr>

<h2>Architecture Block Diagram</h2>

<p>GitHub natively supports Mermaid.js diagrams. Below is the HTML code block representation of the architecture integration (<code>dmac_top</code>) and internal module routing.</p>

<pre><code class="language-mermaid">
flowchart LR
    subgraph DMA_Subsystem["DMA Controller Subsystem"]
        direction TB
        CTRL[dmac_controller]
        FIFO[sync_fifo]
        AXI_M[axi_master]
        AXI_L[axi_lite_slave]

        CTRL &lt;--&gt;|Internal Data/Cmd| FIFO
        CTRL &lt;--&gt;|Tx/Rx/Cmd| AXI_M
        AXI_L --&gt;|Reg Write| CTRL
    end

    CPU((Host CPU)) --&gt;|AXI-Lite| AXI_L
    AXI_M &lt;--&gt;|AXI Full| ROUTER{axi_router}

    ROUTER &lt;--&gt;|Base 0x0000_0000| MEM[axi_slave_memory]
    ROUTER &lt;--&gt;|Base 0x4X00_0000| IO[axi_io_slave 0-7]

    MEM --- SRAM[(Internal RAM)]
    IO --- ROM[(Peripheral ROM/Regs)]
</code></pre>

<hr>

<h2>Memory Map &amp; Registers</h2>

<p>The DMA controller is configured by the CPU via the AXI-Lite interface.</p>

<h3>Control Registers</h3>

<table>
    <thead>
        <tr>
            <th>Offset</th>
            <th>Register Name</th>
            <th>Description</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><strong>0x00</strong></td>
            <td><code>CTRL_REG</code></td>
            <td>Write <code>1</code> to Bit 0 to start (RUN) the DMA engine.</td>
        </tr>
        <tr>
            <td><strong>0x14</strong></td>
            <td><code>CURR_DESC_PTR</code></td>
            <td>Pointer to the first 32-bit address of the descriptor chain.</td>
        </tr>
        <tr>
            <td><strong>0x18</strong></td>
            <td><code>IRQ_CLEAR</code></td>
            <td>Write <code>1</code> to Bit 0 to clear pending hardware interrupts and halt states.</td>
        </tr>
    </tbody>
</table>

<h3>Descriptor Format</h3>

<p>Descriptors are 6 words (24 bytes) long and must be aligned in memory.</p>

<table>
    <thead>
        <tr>
            <th>Word Offset</th>
            <th>Field</th>
            <th>Description</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><strong>0x00</strong></td>
            <td>Link Pointer</td>
            <td>Address of the next descriptor. A value of <code>0x0000_0000</code> indicates the End of Chain (EOF).</td>
        </tr>
        <tr>
            <td><strong>0x04</strong></td>
            <td>Source Address</td>
            <td>The address to read data from.</td>
        </tr>
        <tr>
            <td><strong>0x08</strong></td>
            <td>Dest Address</td>
            <td>The address to write data to.</td>
        </tr>
        <tr>
            <td><strong>0x0C</strong></td>
            <td>Config &amp; Length</td>
            <td>Bits [18:16]: Transfer Size. Bits [15:0]: Transfer Length in Bytes.</td>
        </tr>
        <tr>
            <td><strong>0x10</strong></td>
            <td>User / Reserved</td>
            <td>Reserved for application-specific routing or metadata.</td>
        </tr>
        <tr>
            <td><strong>0x14</strong></td>
            <td>Status</td>
            <td>Bit 0: Ownership (1 = CPU, 0 = DMA). Bits [4:1]: Error Codes (SLVERR, DECERR).</td>
        </tr>
    </tbody>
</table>

<hr>

<h2>Simulation and Testing</h2>

<p>The included testbench (<code>dmac_tb.v</code>) thoroughly verifies the controller's functionality, including memory-to-I/O transfers, I/O-to-memory transfers, and hardware error trapping.</p>

<h3>Running the Testbench</h3>

<ol>
    <li>Ensure you have a Verilog simulator installed (e.g., ModelSim, Verilator, or Icarus Verilog).</li>
    <li>Update the <code>MEM_FILE</code> and <code>INIT_FILE</code> parameters in <code>dmac_top.v</code> to point to valid <code>.hex</code> initialization files on your local machine, or utilize <code>$readmemh</code> with relative paths.</li>
    <li>Compile and run the testbench.</li>
</ol>

<p><strong>Testbench Sequence:</strong></p>
<ul>
    <li>Initializes 23 scatter-gather descriptors in the SRAM.</li>
    <li>Triggers standard transfers across varying burst lengths.</li>
    <li>Intentionally injects an AXI <code>SLVERR</code> by manipulating the transfer size payload.</li>
    <li>Intentionally injects an AXI <code>DECERR</code> by targeting an unmapped memory address (<code>0xDEAD_0000</code>).</li>
    <li>Forces a Descriptor Ownership Error by setting the CPU-ownership bit on an active chain.</li>
    <li>Polls the <code>cpu_intr</code> line and verifies that memory contents precisely match expectations.</li>
</ul>

<hr>

<p><strong>Author:</strong> Vivek Ranjan</p>
