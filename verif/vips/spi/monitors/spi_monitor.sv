///////////////////////////////////////////////////////////////////////////////////////////////////////
// Company:        MICRO-ELECTRONICS RESEARCH LABORATORY                                             //
//                                                                                                   //
// Engineers:      Auringzaib Sabir - Verification                                                   //
//                                                                                                   //
// Additional contributions by:                                                                      //
//                                                                                                   //
// Create Date:    27-MAY-2022                                                                       //
// Design Name:    SPI                                                                               //
// Module Name:    spi_monitor.sv                                                                    //
// Project Name:   VIPs for different peripherals                                                    //
// Language:       SystemVerilog - UVM                                                               //
//                                                                                                   //
// Description:                                                                                      //
// Monitor is parameterize component class, as shown here the monitor get transactions from DUT      //
// and send transaction to other components like scoreboard and coverage collector                   //
//                                                                                                   //
// Revision Date:                                                                                    //
//                                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////////////////////

class spi_monitor extends uvm_monitor;
	// For all uvm_component we have to register them with uvm factory using uvm macro (`uvm_component_utils)
	// Pass the class name to it
  `uvm_component_utils(spi_monitor)

  /*
	Then declare spi_monitor class constructor
	Since a class object has to be constructed before it exit in a memory
	The creation of class hierarchy in a system verilog testbench has to be initiated from a top module.
	Since a module(top module) is static object that is present at beginning of simulation 
	*/
	// Component Constructor have two arguments to specify the name and handle of the parent of this component in testbench topology
	function new(string name, uvm_component parent);
    super.new(name, parent);
	endfunction // new
  
  // Declaring a virtual interface which connects DUT and testbench. Virtual interfaces in system verilog virtual means something is a reference to something else
  // Note tx_agent_config object with virtual interface is present(set) in uvm_config_db
  virtual test_ifc vif;
  tx_agent_config tx_agent_config_h; // Declaration of agent configuraton object
  
  // TLM analysis port
  uvm_analysis_port #(transaction_item) dut_tx_port;
  
  // Build Phase
  function void build_phase(uvm_phase phase);
    `uvm_info("UART_MONITOR::",$sformatf("______BUILD_PHASE______"), UVM_LOW)
    // Creating analysis port TLM analysis ports are not created with factory
    dut_tx_port = new ("dut_tx_port",this);
    if(!uvm_config_db#(tx_agent_config)::get(this/*Handle to this component*/, ""/*an empty instance name*/, "tx_agent_config_h"/*Name of the object in db*/, tx_agent_config_h/*Handle that the db writes to*/))
      `uvm_fatal("spi_monitor::NO AGENT CONFIG",$sformatf("No agent config in db"))
    // Note now you can read the values from config object
    vif = tx_agent_config_h.vif;
    // Display the base address from config object
    `uvm_info(get_type_name(), $sformatf("config base adddress = %0x", tx_agent_config_h.base_address), UVM_LOW)
  endfunction : build_phase
  
  // Run phase
  virtual task run_phase(uvm_phase phase);
    // Function to get transaction from virtual interface
    fork
      capture_control_register();
      get_mosi_tx();
      get_tx_to_be_config();
      get_rx_signals();
      rd_miso_reg();
      count_clk();
      check_tx_interrupt();
    join_none
  endtask
  
  // Declaration
  string msg ="";
  bit [ 76:0] cycle_num = 0                           ;
  int         set                                     ;
  int         clct_mosi                               ;
  int         count                                   ;
  int         data                                    ;
  bit         next_data                               ;
  bit         reg1_slav1_enable                       ;
  bit         reg2_slav1_enable                       ;
  int         count_clock_cycles                      ;
  bit  [31:0] reg1_slav1_collection_q[$]              ;
  bit  [31:0] reg2_slav1_collection_q[$]              ;
  bit  [31:0] chker_reg1_slav1_collection_q[$]        ;
  bit  [31:0] chker_reg2_slav1_collection_q[$]        ;
  int         counter                                 ;
  bit  [31:0] contrl_reg                              ;
  bit  [31:0] mosi_data_collection_q[$]               ;
  bit  [31:0] tb_driven_tx_config_data_collection_q[$];
  bit         lock                                    ;
  bit  [31:0] control_register                        ;


  // Task for capturing control register at every posedge of clock
  virtual task capture_control_register();
    // Transaction Handle declaration
    transaction_item tx_ctrl_reg;
    forever begin
      @(posedge vif.clk_i)
        tx_ctrl_reg = transaction_item::type_id::create("tx_ctrl_reg");
        tx_ctrl_reg.rst_ni  = vif.rst_ni ;        
        tx_ctrl_reg.addr_i  = vif.addr_i ;            
        tx_ctrl_reg.wdata_i = vif.wdata_i;              
        tx_ctrl_reg.be_i    = vif.be_i   ;           
        tx_ctrl_reg.we_i    = vif.we_i   ;       
        tx_ctrl_reg.re_i    = vif.re_i   ;        
        tx_ctrl_reg.sd_i    = vif.sd_i   ;                       // master in slave out
        
        // Assigning counter the value char length that is present in 7 LSB of control register  
        if (tx_ctrl_reg.addr_i == 'h10) begin
          control_register = tx_ctrl_reg.wdata_i;
          `uvm_info("SPI_MONITIOR::", $sformatf("Control register = %0b",control_register), UVM_LOW)
        end
    end
  endtask 
  
  // Task for MOSI (This logic is behaving as a SPI slave devices)
  virtual task get_mosi_tx();
    // Transaction Handle declaration
    transaction_item tx;
    forever begin
      @(posedge vif.sclk_o)
        tx = transaction_item::type_id::create("tx");
        tx.rst_ni  = vif.rst_ni ;        
        tx.addr_i  = vif.addr_i ;            
        tx.wdata_i = vif.wdata_i;              
        tx.be_i    = vif.be_i   ;           
        tx.we_i    = vif.we_i   ;       
        tx.re_i    = vif.re_i   ;        
        tx.sd_i    = vif.sd_i   ;                       // master in slave out
        
        // Collecting tx serial output data on sd_o pin
        clct_mosi[count] = vif.sd_o;
        count = count + 1;

        // Assigning counter the value char length that is present in 7 LSB of control register  
        if (lock == 0) begin
          lock = 1;
          contrl_reg = control_register;
          counter = `CHAR_LENGTH_CTRL_REG/*10*//*contrl_reg[6:0]*/;                                                       // TODO always select the randomize data
          `uvm_info("SPI_MONITIOR::", $sformatf("Printing Counter = %0d",counter), UVM_LOW)
        end

        // Data collection depending on the char length and pushing it in the queue if tx is enabled
        if(count == counter) begin
          data = clct_mosi;
          if(contrl_reg[14]==1) begin
            mosi_data_collection_q.push_front(clct_mosi);
          end
          `uvm_info("SPI_MONITIOR::", $sformatf("Printing the collected mosi = %0b",data), UVM_LOW)
          `uvm_info("SPI_MONITIOR::", $sformatf("Printing the slave select output signal = %0b", vif.ss_o), UVM_LOW)
          // Check if rx is enabled in conrol register and tx is disabled
          if(contrl_reg[8]==1 && contrl_reg[15]==1 && contrl_reg[14]==0) begin
            //wait(vif.intr_rx_o == 1'b1);
            count = 0;
            reg1_slav1_enable = 1'b0;
            reg2_slav1_enable = 1'b0;
            lock = 0;
          end
        end

        // SPI device slave 1
        if(!vif.ss_o[0] && count == counter) begin
          // Checking if rx and tx are enabled simultanously
          if(contrl_reg[8]==1 && contrl_reg[15]==1 && contrl_reg[14]==1) begin
            wait(vif.intr_tx_o == 1'b1);
            count = 0;
            lock = 0;
          end
          `uvm_info("SPI_MONITIOR::", $sformatf("Printing the collected data = %0b",data), UVM_LOW)
          `uvm_info("SPI_MONITIOR::", $sformatf("Enabled Device 1"), UVM_LOW)
          // Check if data send by driver is a command or a data. And if it is command detect either read or write operation is performed
          if(data[1:0] == 2'b11 && data[2] == 1'b1) begin // data[2] == 1 and data[1:0] == 2'b11, that means command data is command and write is to be performed respectively. 
            `uvm_info("SPI_MONITIOR::", $sformatf("Next will be tx data"), UVM_LOW)
            reg1_slav1_enable = 1'b1;
            reg2_slav1_enable = 1'b0;
            `uvm_info("SPI_MONITIOR::", $sformatf("Printing write enable = %0d", reg1_slav1_enable), UVM_LOW)
            count = 0;
            wait(vif.intr_tx_o == 1'b1);
            lock = 0;
          end
          // Check if data send by driver is a command or a data. And if it is command detect either read or write operation is performed
          else if (data[1:0] == 2'b10 && data[2] == 1'b1) begin // data[2] == 1 and data[1:0] == 2'b11, that means command data is command and write is to be performed respectively.
            `uvm_info("SPI_MONITIOR::", $sformatf("Next will be rx data"), UVM_LOW)
            reg1_slav1_enable = 1'b0;
            reg2_slav1_enable = 1'b1;
            count = 0;
            wait(vif.intr_tx_o == 1'b1);
            lock = 0;
          end

          // Write operation is to be performed in reg1
          if (reg1_slav1_enable == 1'b1 && contrl_reg[8]==1 && contrl_reg[14]==1 && (data[2:0] != 3'b111)) begin
             `uvm_info("SPI_MONITIOR::", $sformatf("Coming data is tx"), UVM_LOW)
             `uvm_info("SPI_MONITIOR::", $sformatf("Printing output tx data to be pushed in queue = %0b",data), UVM_LOW)
             reg1_slav1_collection_q.push_front(data);
             count = 0;
             wait(vif.intr_tx_o == 1'b1);
             lock = 0;
          end
          // Write operation is to be performed in reg2
          else if (reg2_slav1_enable == 1'b1 && contrl_reg[8]==1 && contrl_reg[14]==1 && (data[2:0] != 3'b110)) begin
            `uvm_info("SPI_MONITIOR::", $sformatf("Coming data is tx"), UVM_LOW)
            `uvm_info("SPI_MONITIOR::", $sformatf("Printing output tx data to be pushed in queue = %0b",data), UVM_LOW)
            reg2_slav1_collection_q.push_front(data);
            count = 0;
            wait(vif.intr_tx_o == 1'b1);
            lock = 0;
          end
        end
        
        // slave 2
        if(!vif.ss_o[1] && count == 32) begin
          `uvm_info("SPI_MONITIOR::", $sformatf("Enabled Device 2"), UVM_LOW)
        end
        // slave 3
        if(!vif.ss_o[2] && count == 32) begin
          `uvm_info("SPI_MONITIOR::", $sformatf("Enabled Device 3"), UVM_LOW)
        end
        // slave 3
        if(!vif.ss_o[3] && count == 32) begin
          `uvm_info("SPI_MONITIOR::", $sformatf("Enabled Device 4"), UVM_LOW)
        end

    end // forever
  endtask

  // Declaration
  bit  [31:0] length                       ;
  bit  [31:0] data_queued                  ;
  bit  [31:0] ctrl_reg                     ;
  bit  [31:0] drive_data                   ;
  int         num_of_runs                  ;
  bit         chkr_reg1_slav1_drive_data_en;
  bit         chkr_reg2_slav1_drive_data_en;
  bit         wr_en_driving_data           ;
  bit         lock_ctrl_reg                ;
  bit         first_config                 ;
  bit         locked_2                     ;
  bit         check_rx                     ;
  
  // This task is basically a checker logic for MOSI(tx), it captured data from the interface then store in 
  // the queue that is compared afterward with the data store in the slave device
  virtual task get_tx_to_be_config();
    // Transaction Handle declaration
    transaction_item tx;
    forever begin
      @(posedge vif.clk_i)
        tx = transaction_item::type_id::create("tx");
        tx.rst_ni  = vif.rst_ni ;        
        tx.addr_i  = vif.addr_i ;            
        tx.wdata_i = vif.wdata_i;              
        tx.be_i    = vif.be_i   ;           
        tx.we_i    = vif.we_i   ;       
        tx.re_i    = vif.re_i   ;        
        tx.sd_i    = vif.sd_i   ;                       // master in slave out
        
        // Check if the address is 0x00 that means it is data to be configured in the tx register
        if (tx.addr_i == 'h0 && tx.be_i == 'b1111 && tx.we_i == 'h1 && tx.re_i == 'h0) begin
          drive_data = tx.wdata_i;
          // If tx and rx are disabled in control register then do not push data in the queue
          if (first_config == 0 && ctrl_reg[14] == 0 && ctrl_reg[15] == 0) begin
            tb_driven_tx_config_data_collection_q.push_front(drive_data[(`CHAR_LENGTH_CTRL_REG)-1:0]);
            first_config = 1;
          end
          // If tx is enabled in the control register then push data in the queue
          if (ctrl_reg[14] == 1'h1) begin
            tb_driven_tx_config_data_collection_q.push_front(drive_data[(`CHAR_LENGTH_CTRL_REG)-1:0]);
            `uvm_info("SPI_MONITIOR::", $sformatf("Printing drive_data %0b", drive_data), UVM_LOW)
          end
        end
        
        // Check if the address is 0x10, that means control register is configured
        if(tx.addr_i == 'h10 && tx.be_i == 'b1111 && tx.we_i == 1 && tx.re_i == 0) begin
          length = `CHAR_LENGTH_CTRL_REG/*10*//*tx.wdata_i[6:0]*/;
          // Dependent logic to push data in the queue
          if (vif.wdata_i[15] == 1 && vif.wdata_i[14] == 0) begin
            lock_ctrl_reg = 1'b0;
            first_config = 0;
          end
          if (lock_ctrl_reg == 0)
            ctrl_reg = vif.wdata_i;
          `uvm_info("SPI_MONITIOR::", $sformatf("Printing control register ctrl_Reg %b", ctrl_reg), UVM_LOW)
          
          // This logic is to check the data store in the slave's registers/queues specifically tx register/queue
          // First data is a command for a slave device, if command data has 2 lsb equals 'b11 or 'b10, coming data depending on these command
          // will be stored in chker_reg1_slav1_collection_q and chker_reg2_slav1_collection_q respectively
          if (drive_data[1:0] == 2'b11 && drive_data[2] == 1'b1 && ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h1) begin
            chkr_reg1_slav1_drive_data_en = 1'b1;
            chkr_reg2_slav1_drive_data_en = 1'b0;
            lock_ctrl_reg = 1;
          end
          else if (drive_data[1:0] == 2'b10 && drive_data[2] == 1'b1 && ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h1) begin
            chkr_reg1_slav1_drive_data_en = 1'b0;
            chkr_reg2_slav1_drive_data_en = 1'b1;
            lock_ctrl_reg = 1;
          end
          if (ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h0) begin
            chkr_reg1_slav1_drive_data_en = 1'b0;
            chkr_reg2_slav1_drive_data_en = 1'b0;
            lock_ctrl_reg = 0;
          end          
          
          // Logic to push data in chker_reg1_slav1_collection_q
          if (chkr_reg1_slav1_drive_data_en == 1 && drive_data[2:0] != 3'b111 && ctrl_reg[14] == 1'h1) begin
            num_of_runs = num_of_runs + 1'b1;
            for(int index=0; index < length; index=index+1) begin
              data_queued[index] = drive_data[index];
            end
            if (num_of_runs==1) begin
              `uvm_info("SPI_MONITIOR::", $sformatf("Printing data queue %0h", data_queued), UVM_LOW)
              chker_reg1_slav1_collection_q.push_front(data_queued/*tx.wdata_i*/);
              wait(vif.intr_tx_o);
              lock_ctrl_reg = 0;
              `uvm_info("SPI_MONITIOR::", $sformatf("tx_adress %0h", tx.addr_i), UVM_LOW)
              `uvm_info("SPI_MONITIOR::", $sformatf("second run value %0d", num_of_runs), UVM_LOW)
            end 
            if (num_of_runs==2 || ctrl_reg[14]==0) begin
              num_of_runs=0;
            end
          end
          
          // Logic to push data in chker_reg2_slav1_collection_q
          if (chkr_reg2_slav1_drive_data_en == 1 && drive_data[2:0] != 3'b110 && ctrl_reg[14] == 1'h1) begin
            num_of_runs = num_of_runs + 1'b1;
            for(int index=0; index < length; index=index+1) begin
              data_queued[index] = drive_data[index];
            end
            if (num_of_runs==1) begin
              `uvm_info("SPI_MONITIOR::", $sformatf("Printing data queue %0h", data_queued), UVM_LOW)
              chker_reg2_slav1_collection_q.push_front(data_queued/*tx.wdata_i*/);
              wait(vif.intr_tx_o);
              lock_ctrl_reg = 0;
              `uvm_info("SPI_MONITIOR::", $sformatf("tx_adress %0h", tx.addr_i), UVM_LOW)
              `uvm_info("SPI_MONITIOR::", $sformatf("second run value %0d", num_of_runs), UVM_LOW)
            end 
            if (num_of_runs==2 || ctrl_reg[14]==0) begin
              num_of_runs=0;
            end
          end
          
          // Depended Logic/signals to push data in tb_driven_tx_config_data_collection_q
          if (ctrl_reg[15] == 1 && ctrl_reg[14] == 0 && locked_2 == 0) begin
            //tb_driven_tx_config_data_collection_q.delete(0);
            locked_2 = 1;
          end

          if (first_config == 0 && ctrl_reg[14] == 1 && ctrl_reg[15] == 1) begin
            tb_driven_tx_config_data_collection_q.push_front(drive_data[(`CHAR_LENGTH_CTRL_REG)-1:0]);
            first_config = 1;
            // This logic is to check the data store in the slave's registers/queues specifically tx register/queue
            // First data is a command for a slave device, if command data has 2 lsb equals 'b11 or 'b10, coming data depending on these command
            // will be stored in chker_reg1_slav1_collection_q and chker_reg2_slav1_collection_q respectively
            if (drive_data[1:0] == 2'b11 && drive_data[2] == 1'b1 && ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h1) begin
              chkr_reg1_slav1_drive_data_en = 1'b1;
              chkr_reg2_slav1_drive_data_en = 1'b0;
              lock_ctrl_reg = 1;
            end
            else if (drive_data[1:0] == 2'b10 && drive_data[2] == 1'b1 && ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h1) begin
              chkr_reg1_slav1_drive_data_en = 1'b0;
              chkr_reg2_slav1_drive_data_en = 1'b1;
              lock_ctrl_reg = 1;
            end
            if (ctrl_reg[8] == 1'h1 && ctrl_reg[14] == 1'h0) begin
              chkr_reg1_slav1_drive_data_en = 1'b0;
              chkr_reg2_slav1_drive_data_en = 1'b0;
              lock_ctrl_reg = 0;
            end          
          
            // Logic to push data in chker_reg1_slav1_collection_q
            if (chkr_reg1_slav1_drive_data_en == 1 && drive_data[2:0] != 3'b111 && ctrl_reg[14] == 1'h1) begin
              num_of_runs = num_of_runs + 1'b1;
              for(int index=0; index < length; index=index+1) begin
                data_queued[index] = drive_data[index];
              end
              if (num_of_runs==1) begin
                `uvm_info("SPI_MONITIOR::", $sformatf("Printing data queue %0h", data_queued), UVM_LOW)
                chker_reg1_slav1_collection_q.push_front(data_queued/*tx.wdata_i*/);
                wait(vif.intr_tx_o);
                lock_ctrl_reg = 0;
                `uvm_info("SPI_MONITIOR::", $sformatf("tx_adress %0h", tx.addr_i), UVM_LOW)
                `uvm_info("SPI_MONITIOR::", $sformatf("second run value %0d", num_of_runs), UVM_LOW)
              end 
              if (num_of_runs==2 || ctrl_reg[14]==0) begin
                num_of_runs=0;
              end
            end
          
            // Logic to push data in chker_reg2_slav1_collection_q
            if (chkr_reg2_slav1_drive_data_en == 1 && drive_data[2:0] != 3'b110 && ctrl_reg[14] == 1'h1) begin
              num_of_runs = num_of_runs + 1'b1;
              for(int index=0; index < length; index=index+1) begin
                data_queued[index] = drive_data[index];
              end
              if (num_of_runs==1) begin
                `uvm_info("SPI_MONITIOR::", $sformatf("Printing data queue %0h", data_queued), UVM_LOW)
                chker_reg2_slav1_collection_q.push_front(data_queued/*tx.wdata_i*/);
                wait(vif.intr_tx_o);
                lock_ctrl_reg = 0;
                `uvm_info("SPI_MONITIOR::", $sformatf("tx_adress %0h", tx.addr_i), UVM_LOW)
                `uvm_info("SPI_MONITIOR::", $sformatf("second run value %0d", num_of_runs), UVM_LOW)
              end 
              if (num_of_runs==2 || ctrl_reg[14]==0) begin
                num_of_runs=0;
              end
            end
          end 
        end

    end // forever
  endtask

  // Task to check tx interrupt after MOSI is disabled
  virtual task check_tx_interrupt();
  // Transaction Handle declaration
    transaction_item tx_intrpt;
    forever begin
      @(posedge vif.clk_i)
      if (control_register[8]==1 && control_register[14]== 0 && vif.intr_tx_o) begin
        tf();
        `uvm_fatal("FATAL_ID",$sformatf("tx Interrpt when MOSI is disbaled"))
      end
    end // forever
  endtask

  // Task to count the number of output clock cycles
  virtual task count_clk();
    // Transaction Handle declaration
    transaction_item tx;
    forever begin
      @(posedge vif.sclk_o)
        count_clock_cycles = count_clock_cycles + 1;
    end // forever
  endtask

  // Declaration
  bit  [31:0] collect_rx_sd_i[$];
  bit  [31:0] counter_rx_length ;
  bit  [31:0] count_rx_i        ;
  bit  [31:0] rx_data           ;

  // Task to capture the MISO (rx siganls)
  virtual task get_rx_signals();
    // Transaction Handle declaration
    transaction_item rx;
    forever begin
      @(posedge vif.sclk_o)
        rx = transaction_item::type_id::create("rx");
        rx.rst_ni  = vif.rst_ni ;        
        rx.addr_i  = vif.addr_i ;            
        rx.wdata_i = vif.wdata_i;              
        rx.be_i    = vif.be_i   ;           
        rx.we_i    = vif.we_i   ;       
        rx.re_i    = vif.re_i   ;        
        rx.sd_i    = vif.sd_i   ;                       // master in slave out
       
       // Assigning the char length in the control register
       counter_rx_length = `CHAR_LENGTH_CTRL_REG;
       // Collecting input data on sd_i pin that is completely randomize
       rx_data[count_rx_i] = vif.sd_i;
       count_rx_i = count_rx_i+1;
      
      // Collecting the data until counter_rx_length bits are recieved
      if (count_rx_i == counter_rx_length) begin
        `uvm_info("SPI_MONITIOR::", $sformatf("Entering condition when count_rx_i == counter_rx_length\n Printing control register = %0b", control_register), UVM_LOW)
        count_rx_i = 0;
        // Push the collected data in queue if tx is enabled and rx is disabled in the control register
        if (control_register[8] == 1 && control_register[14] == 0 && control_register[15] == 1) begin
          `uvm_info("SPI_MONITIOR::", $sformatf("Pushing data in queue collect_rx_sd_i"), UVM_LOW)
          collect_rx_sd_i.push_front(rx_data);
          wait(vif.intr_rx_o);
        end
      end // count_rx_i == counter_rx_length
    end // forever
  endtask

  // Declaration
  bit  [31:0] rd_miso_reg_q[$];
  bit  [31:0] count_rd_cycle  ;
  
  // Task to capture the read data from the MISO (rx) register
  virtual task rd_miso_reg();
    // Transaction Handle declaration
    transaction_item rd_miso;
    forever begin
      @(posedge vif.clk_i)
        rd_miso = transaction_item::type_id::create("rd_miso");
        rd_miso.rst_ni  = vif.rst_ni ;        
        rd_miso.addr_i  = vif.addr_i ;            
        rd_miso.wdata_i = vif.wdata_i;              
        rd_miso.be_i    = vif.be_i   ;           
        rd_miso.we_i    = vif.we_i   ;       
        rd_miso.re_i    = vif.re_i   ;        
        rd_miso.sd_i    = vif.sd_i   ;                       // master in slave out
        
        // Logic to push the rx regieter read data from the queue
        if (count_rd_cycle == 1)
          count_rd_cycle = count_rd_cycle + 1; 
        if (count_rd_cycle == 2) begin
          rd_miso_reg_q.push_front(vif.rdata_o);
          count_rd_cycle = 0;
        end
        if (rd_miso.addr_i  == 'h20 && rd_miso.be_i == 'b1111 && rd_miso.we_i == 1'h0 && rd_miso.re_i == 1'h1) begin
          count_rd_cycle = count_rd_cycle + 1;          
        end

    end // forever
  endtask

  virtual function void check_phase(uvm_phase phase);
    int mismatch = 0;

    `uvm_info("SPI_MONITIOR::", $sformatf("Print mosi_data_collection_q = %p", mosi_data_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print tb_driven_tx_config_data_collection_q = %p", tb_driven_tx_config_data_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print reg1_slav1_collection_q = %p", reg1_slav1_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print reg2_slav1_collection_q = %p", reg2_slav1_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print chker_reg1_slav1_collection_q = %p", chker_reg1_slav1_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print chker_reg2_slav1_collection_q = %p", chker_reg2_slav1_collection_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print rd_miso_reg_q = %p", rd_miso_reg_q), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print collect_rx_sd_i = %p", collect_rx_sd_i), UVM_LOW)
    `uvm_info("SPI_MONITIOR::", $sformatf("Print Number of clock = %d", count_clock_cycles), UVM_LOW)

    if (mosi_data_collection_q == tb_driven_tx_config_data_collection_q)
      `uvm_info(get_type_name(), $sformatf("[COMPARISON PASSED] Drived data & MOSI"), UVM_LOW)
    else begin
      `uvm_error("ERROR_1",$sformatf("COMPARISON FAILED] Drived data and MOSI"))
      mismatch = mismatch + 1;
    end
    if (reg1_slav1_collection_q == chker_reg1_slav1_collection_q)
      `uvm_info(get_type_name(), $sformatf("[COMPARISON PASSED] :: reg1_slav1_collection_q == chker_reg1_slav1_collection_q "), UVM_LOW)
    else begin
      `uvm_error("ERROR_2",$sformatf("COMPARISON FAILED] :: reg1_slav1_collection_q != chker_reg1_slav1_collection_q "))
      mismatch = mismatch + 1;
    end
    if (reg2_slav1_collection_q == chker_reg2_slav1_collection_q)
      `uvm_info(get_type_name(), $sformatf("[COMPARISON PASSED] :: reg2_slav1_collection_q == chker_reg2_slav1_collection_q "), UVM_LOW)
    else begin
      `uvm_error("ERROR_3",$sformatf("COMPARISON FAILED] :: reg2_slav1_collection_q != chker_reg2_slav1_collection_q"))
      mismatch = mismatch + 1;
    end
    if (rd_miso_reg_q == collect_rx_sd_i)
      `uvm_info(get_type_name(), $sformatf("[COMPARISON PASSED] :: rd_miso_reg_q == collect_rx_sd_i "), UVM_LOW)
    else begin
      `uvm_error("ERROR_4",$sformatf("COMPARISON FAILED] :: rd_miso_reg_q != collect_rx_sd_i "))
      mismatch = mismatch + 1;
    end
    
    if (mismatch != 0)
      tf();
    else
      tp();
  endfunction

  function void tp();
    msg = "";
    $sformat(msg, "%s\n\n████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗███████╗██████╗  ", msg);
    $sformat(msg, "%s\n╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗ ", msg);
    $sformat(msg, "%s\n   ██║   █████╗  ███████╗   ██║       ██████╔╝███████║███████╗███████╗█████╗  ██║  ██║ ", msg);
    $sformat(msg, "%s\n   ██║   ██╔══╝  ╚════██║   ██║       ██╔═══╝ ██╔══██║╚════██║╚════██║██╔══╝  ██║  ██║ ", msg);
    $sformat(msg, "%s\n   ██║   ███████╗███████║   ██║       ██║     ██║  ██║███████║███████║███████╗██████╔╝ ", msg);
    $sformat(msg, "%s\n   ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═════╝  \n", msg);
    `uvm_info("TEST STATUS::",$sformatf("\n", msg), UVM_LOW)
  endfunction : tp
  
  function void tf();
    msg = "";
    $sformat(msg, "%s\n\n ████████╗███████╗███████╗████████╗    ███████╗ █████╗ ██╗██╗     ███████╗██████╗ ", msg);
    $sformat(msg, "%s\n ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔════╝██╔══██╗██║██║     ██╔════╝██╔══██╗", msg);
    $sformat(msg, "%s\n    ██║   █████╗  ███████╗   ██║       █████╗  ███████║██║██║     █████╗  ██║  ██║", msg);
    $sformat(msg, "%s\n    ██║   ██╔══╝  ╚════██║   ██║       ██╔══╝  ██╔══██║██║██║     ██╔══╝  ██║  ██║", msg);
    $sformat(msg, "%s\n    ██║   ███████╗███████║   ██║       ██║     ██║  ██║██║███████╗███████╗██████╔╝", msg);
    $sformat(msg, "%s\n    ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ \n", msg);
     `uvm_info("TEST STATUS::",$sformatf("\n", msg), UVM_LOW)                     
  endfunction : tf

endclass

