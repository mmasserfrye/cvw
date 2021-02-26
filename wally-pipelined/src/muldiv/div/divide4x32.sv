module int32div (Q, done, divdone, rem0, div0, N, D, clk, reset, start);

   input logic [31:0]  N, D;
   input logic 	       clk;
   input logic 	       reset;
   input logic 	       start;
   
   output logic [31:0] Q;
   output logic [31:0] rem0;
   output logic        div0;
   output logic        done;
   output logic        divdone;   

   logic 	       enable;
   logic 	       state0;
   logic 	       V;   
   logic [5:0] 	       Num;
   logic [4:0] 	       P, NumIter, RemShift;
   logic [31:0]        op1, op2, op1shift, Rem5;
   logic [32:0]        Qd, Rd, Qd2, Rd2;
   logic [3:0] 	       quotient;
   logic 	       otfzero;   

   // Divider goes the distance to 19 cycles
   // (thanks the evil divisor for D = 0x1) 
   // but could theoretically be stopped when
   // divdone is asserted.  The enable signal
   // turns off register storage thus invalidating
   // any future cycles.
   
   // Shift D, if needed (for integer)
   // needed to allow qst to be in range for integer
   // division [1,2) and allow integer divide to work.
   //
   // The V or valid bit can be used to determine if D
   // is 0 and thus a divide by 0 exception.  This div0
   // exception is given to FSM to tell the operation to 
   // quit gracefully.

   // div0 produced output  errors have untested results
   // (it is assumed the OS would handle some output)
   
   lz32 p1 (P, V, D);
   shifter_l32 p2 (op2, D, P);
   assign op1 = N;
   assign div0 = ~V;

   // Brent-Kung adder chosen for the heck of it and
   // since so small (maybe could have used a RCA)
   
   // #iter: N = m+v+s = m+(s+2) = m+2+s (mod k = 0)
   // v = 2 since \rho < 1 (add 4 to make sure its a ceil)
   bk6 cpa1 (co1, Num, {1'b0, P}, 
	     {3'h0, shiftResult, ~shiftResult,1'b0}, 1'b0);
   
   // Determine whether need to add just Q/Rem
   assign shiftResult = P[0];   
   // div by 2 (ceil)
   assign NumIter = Num[5:1];   
   assign RemShift = P;

   // FSM to control integer divider
   //   assume inputs are postive edge and
   //   datapath (divider) is negative edge
   fsm32 fsm1 (enablev, state0v, donev, divdonev, otfzerov,
	       start, div0, NumIter, ~clk, reset);

   flopr #(1) rega (~clk, reset, donev, done);
   flopr #(1) regb (~clk, reset, divdonev, divdone);
   flopr #(1) regc (~clk, reset, otfzerov, otfzero);
   flopr #(1) regd (~clk, reset, enablev, enable);
   flopr #(1) rege (~clk, reset, state0v, state0);   
  
   // To obtain a correct remainder the last bit of the
   // quotient has to be aligned with a radix-r boundary.
   // Since the quotient is in the range 1/2 < q < 2 (one
   // integer bit and m fractional bits), this is achieved by
   // shifting N right by v+s so that (m+v+s) mod k = 0.  And,
   // the quotient has to be aligned to the integer position.

   // Used a Brent-Kung for no reason (just wanted prefix -- might
   // have gotten away with a RCA)
   
   // Actual divider unit FIXME: r16 (jes)
   divide4x32 p3 (Qd, Rd, quotient, op1, op2, clk, reset, state0, 
		  enable, otfzero, shiftResult);

   // Storage registers to hold contents stable
   flopenr #(33) reg3 (clk, reset, enable, Rd, Rd2);
   flopenr #(33) reg4 (clk, reset, enable, Qd, Qd2);         

   // Probably not needed - just assigns results
   assign Q = Qd2[31:0];
   assign Rem5 = Rd2[32:1];  
   
   // Adjust remainder by m (no need to adjust by
   // n ln(r)
   shifter_r32 p4 (rem0, Rem5, RemShift);

endmodule // int32div

module divide4x32 (Q, rem0, quotient, op1, op2, clk, reset, state0, 
		   enable, otfzero, shiftResult); 

   input logic [31:0]   op1, op2;
   input logic 		clk, state0;
   input logic 		reset;
   input logic 		enable;
   input logic 		otfzero;
   input logic 		shiftResult;   
   
   output logic [32:0] 	rem0;
   output logic [32:0] 	Q;
   output logic [3:0] 	quotient;   

   logic [35:0] 	Sum, Carry;   
   logic [32:0] 	Qstar;   
   logic [32:0] 	QMstar;   
   logic [7:0] 		qtotal;   
   logic [35:0] 	SumN, CarryN, SumN2, CarryN2;
   logic [35:0] 	divi1, divi2, divi1c, divi2c, dive1;
   logic [35:0] 	mdivi_temp, mdivi;   
   logic 		zero;
   logic [1:0] 		qsel;
   logic [1:0] 		Qin, QMin;
   logic 		CshiftQ, CshiftQM;
   logic [35:0] 	rem1, rem2, rem3;
   logic [35:0] 	SumR, CarryR;
   logic [32:0] 	Qt;   

   // Create one's complement values of Divisor (for q*D)
   assign divi1 = {3'h0, op2, 1'b0};
   assign divi2 = {2'h0, op2, 2'b0};
   assign divi1c = ~divi1;
   assign divi2c = ~divi2;
   // Shift x1 if not mod k
   mux2 #(36) mx1 ({3'b000, op1, 1'b0},  {4'h0, op1}, shiftResult, dive1);   

   // I I I . F F F F F ... (Robertson Criteria - \rho * qmax * D)
   mux2 #(36) mx2 ({CarryN2[33:0], 2'h0}, 36'h0, state0, CarryN);
   mux2 #(36) mx3 ({SumN2[33:0], 2'h0}, dive1, state0, SumN);
   // Simplify QST
   adder #(8) cpa1 (SumN[35:28], CarryN[35:28], qtotal);   
   // q = {+2, +1, -1, -2} else q = 0
   qst4 pd1 (qtotal[7:1], divi1[31:29], quotient);
   assign ulp = quotient[2]|quotient[3];
   assign zero = ~(quotient[3]|quotient[2]|quotient[1]|quotient[0]);
   // Map to binary encoding
   assign qsel[1] = quotient[3]|quotient[2];
   assign qsel[0] = quotient[3]|quotient[1];   
   mux4 #(36) mx4 (divi2, divi1, divi1c, divi2c, qsel, mdivi_temp);
   mux2 #(36) mx5 (mdivi_temp, 36'h0, zero, mdivi);
   csa #(36) csa1 (mdivi, SumN, {CarryN[35:1], ulp}, Sum, Carry);
   // regs : save CSA
   flopenr #(36) reg1 (clk, reset, enable, Sum, SumN2);
   flopenr #(36) reg2 (clk, reset, enable, Carry, CarryN2);
   // OTF
   ls_control otf1 (quotient, Qin, QMin, CshiftQ, CshiftQM);   
   otf #(33) otf2 (Qin, QMin, CshiftQ, CshiftQM, clk, 
		   otfzero, enable, Qstar, QMstar);

   // Correction and generation of Remainder
   add36 cpa2 (cout1, rem1, SumN2[35:0], CarryN2[35:0], 1'b0);
   // Add back +D as correction
   csa #(36) csa2 (CarryN2[35:0], SumN2[35:0], divi1, SumR, CarryR);
   add36 cpa3 (cout2, rem2, SumR, CarryR, 1'b0);
   // Choose remainder (Rem or Rem+D)
   mux2 #(36) mx6 (rem1, rem2, rem1[35], rem3);
   // Choose correct Q or QM
   mux2 #(33) mx7 (Qstar, QMstar, rem1[35], Qt);
   // Final results
   assign rem0 = rem3[32:0];
   assign Q = Qt;   
   
endmodule // divide4x32

module ls_control (quot, Qin, QMin, CshiftQ, CshiftQM);

    input logic [3:0] quot;

    output logic [1:0] Qin;
    output logic [1:0] QMin;
    output logic       CshiftQ;
    output logic       CshiftQM;

    assign Qin[1] = (quot[1]) | (quot[3]) | (quot[0]);
    assign Qin[0] = (quot[1]) | (quot[2]);
    assign QMin[1] = (quot[1]) | (!quot[3]&!quot[2]&!quot[1]&!quot[0]);
    assign QMin[0] = (quot[3]) | (quot[0]) | 
		     (!quot[3]&!quot[2]&!quot[1]&!quot[0]);
    assign CshiftQ = (quot[1]) | (quot[0]);
    assign CshiftQM = (quot[3]) | (quot[2]);   

 endmodule 

module otf #(parameter WIDTH=8) 
   (Qin, QMin, CshiftQ, CshiftQM, clk, reset, enable, R2Q, R1Q);
   
   input logic [1:0]        Qin, QMin;
   input logic 		    CshiftQ, CshiftQM;   
   input logic 		    clk;
   input logic 	            reset;
   input logic 		    enable;   

   output logic [WIDTH-1:0] R2Q;
   output logic [WIDTH-1:0] R1Q;   

   logic [WIDTH-1:0] 	    Qstar, QMstar;      
   logic [WIDTH-1:0] 	    M1Q, M2Q;
   
   // QM
   mux2 #(WIDTH)  m1 (QMstar, Qstar, CshiftQM, M1Q);
   flopenr #(WIDTH) r1 (clk, reset, enable, {M1Q[WIDTH-3:0], QMin}, R1Q);
   // Q
   mux2 #(WIDTH)  m2 (Qstar, QMstar, CshiftQ, M2Q);
   flopenr #(WIDTH) r2 (clk, reset, enable, {M2Q[WIDTH-3:0], Qin}, R2Q);
   
   assign Qstar = R2Q;
   assign QMstar = R1Q;

 endmodule // otf8

 module adder #(parameter WIDTH=8) (input logic [WIDTH-1:0] a, b,
				    output logic [WIDTH-1:0] y);
    assign y = a + b;

 endmodule // adder

 module fa (input logic a, b, c, output logic sum, carry);

    assign sum = a^b^c;
    assign carry = a&b|a&c|b&c;   

 endmodule // fa

// Modular Carry-Save Adder
 module csa #(parameter WIDTH=8) (input logic [WIDTH-1:0] a, b, c,
				  output logic [WIDTH-1:0] sum, carry);

    logic [WIDTH:0] 					  carry_temp;   
    genvar 						  i;
    generate
       for (i=0;i<WIDTH;i=i+1)
	 begin : genbit
	    fa fa_inst (a[i], b[i], c[i], sum[i], carry_temp[i+1]);
	 end
    endgenerate
    assign carry = {1'b0, carry_temp[WIDTH-1:1], 1'b0};     

 endmodule // adder

module flopenr #(parameter WIDTH = 8) 
   (input logic clk, reset, en,
    input logic [WIDTH-1:0] d, output logic [WIDTH-1:0] q);

    always_ff @(posedge clk, posedge reset) 
      if (reset) q <= 0; 
      else if (en) q <= d;

endmodule // flopenr

module flopr #(parameter WIDTH = 8) 
   (input logic clk, reset, input
    logic [WIDTH-1:0] d, output logic [WIDTH-1:0] q);

    always_ff @(posedge clk, posedge reset) 
      if (reset) q <= 0; 
      else q <= d;

endmodule // flopr

module flopenrc #(parameter WIDTH = 8) 
   (input logic clk, reset, en, clear, 
    input logic [WIDTH-1:0] d, output logic [WIDTH-1:0] q);

    always_ff @(posedge clk, posedge reset) 
      if (reset) q <= 0; 
      else 
	if (en) 
	  if (clear) q <= 0; 
	  else q <= d;

endmodule // flopenrc

module floprc #(parameter WIDTH = 8) 
   (input logic clk, reset, clear,
    input logic [WIDTH-1:0] d, output logic [WIDTH-1:0] q);

    always_ff @(posedge clk, posedge reset) 
      if (reset) q <= 0; 
      else 
	if (clear) q <= 0; 
	else q <= d;

 endmodule // floprc

 module eqcmp #(parameter WIDTH = 8)
    (input  logic [WIDTH-1:0] a, b,
     output logic             y);

    assign y = (a == b);

 endmodule // eqcmp

// QST : probably want to change to always_comb
 module qst4 (input logic [6:0] s, input logic [2:0] d,
	      output logic [3:0] q);


    assign q[3] = (!s[6]&s[5]) | (!d[2]&!s[6]&s[4]) | (!s[6]&s[4]&s[3]) | 
		  (!d[1]&!s[6]&s[4]&s[2]) | (!d[0]&!s[6]&s[4]&s[2]) | 
		  (!d[1]&!d[0]&!s[6]&s[4]&s[1]) | 
		  (!d[2]&!d[1]&!d[0]&!s[6]&s[3]&s[2]) | 
		  (!d[2]&!d[1]&!s[6]&s[3]&s[2]&s[1]) | 
		  (!d[2]&!d[0]&!s[6]&s[3]&s[2]&s[1]&s[0]);

    assign q[2] = (d[2]&!s[6]&!s[5]&!s[4]&s[3]) | 
		  (!s[6]&!s[5]&!s[4]&s[3]&!s[2]) | 
		  (!d[2]&!s[6]&!s[5]&!s[4]&!s[3]&s[2]) | 
		  (d[2]&d[1]&d[0]&!s[6]&!s[5]&s[4]&!s[3]) | 
		  (d[2]&d[1]&!s[6]&!s[5]&s[4]&!s[3]&!s[2]) | 
		  (d[2]&d[0]&!s[6]&!s[5]&s[4]&!s[3]&!s[2]) | 
		  (d[2]&!s[6]&!s[5]&s[4]&!s[3]&!s[2]&!s[1]) | 
		  (!d[2]&d[1]&d[0]&!s[6]&!s[5]&!s[4]&s[2]) | 
		  (!d[1]&!s[6]&!s[5]&!s[4]&!s[3]&s[2]&s[1]) | 
		  (!d[2]&d[1]&!s[6]&!s[5]&!s[4]&s[2]&!s[1]) | 
		  (!d[2]&d[0]&!s[6]&!s[5]&!s[4]&s[2]&!s[1]) | 
		  (!d[2]&d[1]&!s[6]&!s[5]&!s[4]&s[2]&!s[0]);

    assign q[1] = (d[2]&s[6]&s[5]&s[4]&!s[3]) | 
		  (d[1]&s[6]&s[5]&s[4]&!s[3]) | (s[6]&s[5]&s[4]&!s[3]&s[2]) | 
		  (d[2]&s[6]&s[5]&!s[4]&s[3]&s[2]) | 
		  (d[0]&s[6]&s[5]&s[4]&!s[3]&s[1]) | 
		  (d[2]&d[1]&d[0]&s[6]&s[5]&!s[4]&s[3]) | 
		  (d[2]&d[1]&s[6]&s[5]&!s[4]&s[3]&s[1]) | 
		  (!d[2]&s[6]&s[5]&s[4]&s[3]&!s[2]&!s[1]) | 
		  (!d[2]&!d[1]&!d[0]&s[6]&s[5]&s[4]&s[3]&!s[2]) | 
		  (d[1]&d[0]&s[6]&s[5]&!s[4]&s[3]&s[2]&s[1]) | 
		  (!d[2]&d[0]&s[6]&s[5]&s[4]&!s[2]&!s[1]&s[0]) | 
		  (!d[2]&!d[1]&!d[0]&s[6]&s[5]&s[4]&!s[2]&s[1]&s[0]);

    assign q[0] = (s[6]&!s[5]) | (s[6]&!s[4]&!s[3]) | 
		  (!d[2]&!d[1]&s[6]&!s[4]) | (!d[2]&!d[0]&s[6]&!s[4]) | 
		  (!d[2]&s[6]&!s[4]&!s[2]) | (!d[1]&s[6]&!s[4]&!s[2]) | 
		  (!d[2]&s[6]&!s[4]&!s[1]) | (!d[0]&s[6]&!s[4]&!s[2]&!s[1]) | 
		  (!d[2]&!d[1]&!d[0]&s[6]&!s[3]&!s[2]&!s[1]) | 
		  (!d[2]&!d[1]&!d[0]&s[6]&!s[3]&!s[2]&!s[0]) | 
		  (!d[2]&!d[1]&s[6]&!s[3]&!s[2]&!s[1]&!s[0]);

 endmodule // qst4

// Ladner-Fischer Prefix Adder

module add36 (cout, sum, a, b, cin);
	 
   input logic [35:0]  a, b;
   input logic 	       cin;
   output logic [35:0] sum;
   output logic        cout;
   
   logic [36:0]        p,g;
   logic [35:0]        c;
   
   // pre-computation
   assign p={a^b,1'b0};
   assign g={a&b, cin};
   
   // prefix tree
   ladner_fischer36 prefix_tree(c, p[35:0], g[35:0]);
   
   // post-computation
   assign sum=p[36:1]^c;
   assign cout=g[36]|(p[36]&c[35]);
   
endmodule // add36

module ladner_fischer36 (c, p, g);
	
   input logic [35:0]  p;
   input logic [35:0]  g;
   
   output logic [36:1] c;
   
   // parallel-prefix, Ladner-Fischer
   
   // Stage 1: Generates G/P pairs that span 1 bits
   grey b_1_0 (G_1_0, {g[1],g[0]}, p[1]);
   black b_3_2 (G_3_2, P_3_2, {g[3],g[2]}, {p[3],p[2]});
   black b_5_4 (G_5_4, P_5_4, {g[5],g[4]}, {p[5],p[4]});
   black b_7_6 (G_7_6, P_7_6, {g[7],g[6]}, {p[7],p[6]});
   black b_9_8 (G_9_8, P_9_8, {g[9],g[8]}, {p[9],p[8]});
   black b_11_10 (G_11_10, P_11_10, {g[11],g[10]}, {p[11],p[10]});
   black b_13_12 (G_13_12, P_13_12, {g[13],g[12]}, {p[13],p[12]});
   black b_15_14 (G_15_14, P_15_14, {g[15],g[14]}, {p[15],p[14]});
   
   black b_17_16 (G_17_16, P_17_16, {g[17],g[16]}, {p[17],p[16]});
   black b_19_18 (G_19_18, P_19_18, {g[19],g[18]}, {p[19],p[18]});
   black b_21_20 (G_21_20, P_21_20, {g[21],g[20]}, {p[21],p[20]});
   black b_23_22 (G_23_22, P_23_22, {g[23],g[22]}, {p[23],p[22]});
   black b_25_24 (G_25_24, P_25_24, {g[25],g[24]}, {p[25],p[24]});
   black b_27_26 (G_27_26, P_27_26, {g[27],g[26]}, {p[27],p[26]});
   black b_29_28 (G_29_28, P_29_28, {g[29],g[28]}, {p[29],p[28]});
   black b_31_30 (G_31_30, P_31_30, {g[31],g[30]}, {p[31],p[30]});
   
   black b_33_32 (G_33_32, P_33_32, {g[33],g[32]}, {p[33],p[32]});
   black b_35_34 (G_35_34, P_35_34, {g[35],g[34]}, {p[35],p[34]});
   
   // Stage 2: Generates G/P pairs that span 2 bits
   grey g_3_0 (G_3_0, {G_3_2,G_1_0}, P_3_2);
   black b_7_4 (G_7_4, P_7_4, {G_7_6,G_5_4}, {P_7_6,P_5_4});
   black b_11_8 (G_11_8, P_11_8, {G_11_10,G_9_8}, {P_11_10,P_9_8});
   black b_15_12 (G_15_12, P_15_12, {G_15_14,G_13_12}, {P_15_14,P_13_12});
   black b_19_16 (G_19_16, P_19_16, {G_19_18,G_17_16}, {P_19_18,P_17_16});
   black b_23_20 (G_23_20, P_23_20, {G_23_22,G_21_20}, {P_23_22,P_21_20});
   black b_27_24 (G_27_24, P_27_24, {G_27_26,G_25_24}, {P_27_26,P_25_24});
   black b_31_28 (G_31_28, P_31_28, {G_31_30,G_29_28}, {P_31_30,P_29_28});
   
   black b_35_32 (G_35_32, P_35_32, {G_35_34,G_33_32}, {P_35_34,P_33_32});
   
   // Stage 3: Generates G/P pairs that span 4 bits
   grey g_5_0 (G_5_0, {G_5_4,G_3_0}, P_5_4);
   grey g_7_0 (G_7_0, {G_7_4,G_3_0}, P_7_4);
   black b_13_8 (G_13_8, P_13_8, {G_13_12,G_11_8}, {P_13_12,P_11_8});
   black b_15_8 (G_15_8, P_15_8, {G_15_12,G_11_8}, {P_15_12,P_11_8});
   black b_21_16 (G_21_16, P_21_16, {G_21_20,G_19_16}, {P_21_20,P_19_16});
   black b_23_16 (G_23_16, P_23_16, {G_23_20,G_19_16}, {P_23_20,P_19_16});
   black b_29_24 (G_29_24, P_29_24, {G_29_28,G_27_24}, {P_29_28,P_27_24});
   black b_31_24 (G_31_24, P_31_24, {G_31_28,G_27_24}, {P_31_28,P_27_24});
   
   black b_37_32 (G_37_32, P_37_32, {G_37_36,G_35_32}, {P_37_36,P_35_32});
   black b_39_32 (G_39_32, P_39_32, {G_39_36,G_35_32}, {P_39_36,P_35_32});
   
   // Stage 4: Generates G/P pairs that span 8 bits
   grey g_9_0 (G_9_0, {G_9_8,G_7_0}, P_9_8);
   grey g_11_0 (G_11_0, {G_11_8,G_7_0}, P_11_8);
   grey g_13_0 (G_13_0, {G_13_8,G_7_0}, P_13_8);
   grey g_15_0 (G_15_0, {G_15_8,G_7_0}, P_15_8);
   black b_25_16 (G_25_16, P_25_16, {G_25_24,G_23_16}, {P_25_24,P_23_16});
   black b_27_16 (G_27_16, P_27_16, {G_27_24,G_23_16}, {P_27_24,P_23_16});
   black b_29_16 (G_29_16, P_29_16, {G_29_24,G_23_16}, {P_29_24,P_23_16});
   black b_31_16 (G_31_16, P_31_16, {G_31_24,G_23_16}, {P_31_24,P_23_16});
   
   black b_41_32 (G_41_32, P_41_32, {G_41_40,G_39_32}, {P_41_40,P_39_32});
   black b_43_32 (G_43_32, P_43_32, {G_43_40,G_39_32}, {P_43_40,P_39_32});
   black b_45_32 (G_45_32, P_45_32, {G_45_40,G_39_32}, {P_45_40,P_39_32});
   black b_47_32 (G_47_32, P_47_32, {G_47_40,G_39_32}, {P_47_40,P_39_32});
   
   // Stage 5: Generates G/P pairs that span 16 bits
   grey g_17_0 (G_17_0, {G_17_16,G_15_0}, P_17_16);
   grey g_19_0 (G_19_0, {G_19_16,G_15_0}, P_19_16);
   grey g_21_0 (G_21_0, {G_21_16,G_15_0}, P_21_16);
   grey g_23_0 (G_23_0, {G_23_16,G_15_0}, P_23_16);
   grey g_25_0 (G_25_0, {G_25_16,G_15_0}, P_25_16);
   grey g_27_0 (G_27_0, {G_27_16,G_15_0}, P_27_16);
   grey g_29_0 (G_29_0, {G_29_16,G_15_0}, P_29_16);
   grey g_31_0 (G_31_0, {G_31_16,G_15_0}, P_31_16);
   
   black b_49_32 (G_49_32, P_49_32, {G_49_48,G_47_32}, {P_49_48,P_47_32});
   black b_51_32 (G_51_32, P_51_32, {G_51_48,G_47_32}, {P_51_48,P_47_32});
   black b_53_32 (G_53_32, P_53_32, {G_53_48,G_47_32}, {P_53_48,P_47_32});
   black b_55_32 (G_55_32, P_55_32, {G_55_48,G_47_32}, {P_55_48,P_47_32});
   black b_57_32 (G_57_32, P_57_32, {G_57_48,G_47_32}, {P_57_48,P_47_32});
   black b_59_32 (G_59_32, P_59_32, {G_59_48,G_47_32}, {P_59_48,P_47_32});
   black b_61_32 (G_61_32, P_61_32, {G_61_48,G_47_32}, {P_61_48,P_47_32});
   black b_63_32 (G_63_32, P_63_32, {G_63_48,G_47_32}, {P_63_48,P_47_32});   
   
   // Stage 6: Generates G/P pairs that span 32 bits
   grey g_33_0 (G_33_0, {G_33_32,G_31_0}, P_33_32);
   grey g_35_0 (G_35_0, {G_35_32,G_31_0}, P_35_32);
   grey g_37_0 (G_37_0, {G_37_32,G_31_0}, P_37_32);
   grey g_39_0 (G_39_0, {G_39_32,G_31_0}, P_39_32);
   grey g_41_0 (G_41_0, {G_41_32,G_31_0}, P_41_32);
   grey g_43_0 (G_43_0, {G_43_32,G_31_0}, P_43_32);
   grey g_45_0 (G_45_0, {G_45_32,G_31_0}, P_45_32);
   grey g_47_0 (G_47_0, {G_47_32,G_31_0}, P_47_32);
   
   grey g_49_0 (G_49_0, {G_49_32,G_31_0}, P_49_32);
   grey g_51_0 (G_51_0, {G_51_32,G_31_0}, P_51_32);
   grey g_53_0 (G_53_0, {G_53_32,G_31_0}, P_53_32);
   grey g_55_0 (G_55_0, {G_55_32,G_31_0}, P_55_32);
   grey g_57_0 (G_57_0, {G_57_32,G_31_0}, P_57_32);
   grey g_59_0 (G_59_0, {G_59_32,G_31_0}, P_59_32);
   grey g_61_0 (G_61_0, {G_61_32,G_31_0}, P_61_32);
   grey g_63_0 (G_63_0, {G_63_32,G_31_0}, P_63_32);
   
   // Extra grey cell stage 
   grey g_2_0 (G_2_0, {g[2],G_1_0}, p[2]);
   grey g_4_0 (G_4_0, {g[4],G_3_0}, p[4]);
   grey g_6_0 (G_6_0, {g[6],G_5_0}, p[6]);
   grey g_8_0 (G_8_0, {g[8],G_7_0}, p[8]);
   grey g_10_0 (G_10_0, {g[10],G_9_0}, p[10]);
   grey g_12_0 (G_12_0, {g[12],G_11_0}, p[12]);
   grey g_14_0 (G_14_0, {g[14],G_13_0}, p[14]);
   grey g_16_0 (G_16_0, {g[16],G_15_0}, p[16]);
   grey g_18_0 (G_18_0, {g[18],G_17_0}, p[18]);
   grey g_20_0 (G_20_0, {g[20],G_19_0}, p[20]);
   grey g_22_0 (G_22_0, {g[22],G_21_0}, p[22]);
   grey g_24_0 (G_24_0, {g[24],G_23_0}, p[24]);
   grey g_26_0 (G_26_0, {g[26],G_25_0}, p[26]);
   grey g_28_0 (G_28_0, {g[28],G_27_0}, p[28]);
   grey g_30_0 (G_30_0, {g[30],G_29_0}, p[30]);
   grey g_32_0 (G_32_0, {g[32],G_31_0}, p[32]);
   grey g_34_0 (G_34_0, {g[34],G_33_0}, p[34]);
   
   // Final Stage: Apply c_k+1=G_k_0
   assign c[1]=g[0];
   assign c[2]=G_1_0;
   assign c[3]=G_2_0;
   assign c[4]=G_3_0;
   assign c[5]=G_4_0;
   assign c[6]=G_5_0;
   assign c[7]=G_6_0;
   assign c[8]=G_7_0;
   assign c[9]=G_8_0;
   
   assign c[10]=G_9_0;
   assign c[11]=G_10_0;
   assign c[12]=G_11_0;
   assign c[13]=G_12_0;
   assign c[14]=G_13_0;
   assign c[15]=G_14_0;
   assign c[16]=G_15_0;
   assign c[17]=G_16_0;
   
   assign c[18]=G_17_0;
   assign c[19]=G_18_0;
   assign c[20]=G_19_0;
   assign c[21]=G_20_0;
   assign c[22]=G_21_0;
   assign c[23]=G_22_0;
   assign c[24]=G_23_0;
   assign c[25]=G_24_0;
   
   assign c[26]=G_25_0;
   assign c[27]=G_26_0;
   assign c[28]=G_27_0;
   assign c[29]=G_28_0;
   assign c[30]=G_29_0;
   assign c[31]=G_30_0;
   assign c[32]=G_31_0;
   assign c[33]=G_32_0;
   
   assign c[34]=G_33_0;
   assign c[35]=G_34_0;
   assign c[36]=G_35_0;

endmodule // ladner_fischer36

// Brent-Kung Prefix Adder
module bk6 (cout, sum, a, b, cin);
   
   input logic [5:0]  a, b;
   input logic 	      cin;
   
   output logic [5:0] sum;
   output logic       cout;

   logic [6:0] 	      p,g;
   logic [5:0] 	      c;

   // pre-computation
   assign p={a^b,1'b0};
   assign g={a&b, cin};

   // prefix tree
   brent_kung prefix_tree(c, p[5:0], g[5:0]);

   // post-computation
   assign sum=p[6:1]^c;
   assign cout=g[6]|(p[6]&c[5]);

endmodule // bk6

module brent_kung (c, p, g);
   
   input logic [5:0]  p;
   input logic [5:0]  g;
   
   output logic [6:1] c;

   // parallel-prefix, Brent-Kung
   // Stage 1: Generates G/P pairs that span 1 bits
   grey b_1_0 (G_1_0, {g[1],g[0]}, p[1]);
   black b_3_2 (G_3_2, P_3_2, {g[3],g[2]}, {p[3],p[2]});
   black b_5_4 (G_5_4, P_5_4, {g[5],g[4]}, {p[5],p[4]});

   // Stage 2: Generates G/P pairs that span 2 bits
   grey g_3_0 (G_3_0, {G_3_2,G_1_0}, P_3_2);

   // Stage 3: Generates G/P pairs that span 4 bits

   // Stage 4: Generates G/P pairs that span 2 bits
   grey g_5_0 (G_5_0, {G_5_4,G_3_0}, P_5_4);

   // Last grey cell stage 
   grey g_2_0 (G_2_0, {g[2],G_1_0}, p[2]);
   grey g_4_0 (G_4_0, {g[4],G_3_0}, p[4]);

   // Final Stage: Apply c_k+1=G_k_0
   assign c[1]=g[0];
   assign c[2]=G_1_0;
   assign c[3]=G_2_0;
   assign c[4]=G_3_0;
   assign c[5]=G_4_0;
   assign c[6]=G_5_0;

endmodule // brent_kung

// Black cell
module black (gout, pout, gin, pin);

   input logic [1:0] gin, pin;
   output logic      gout, pout;

   assign pout=pin[1]&pin[0];
   assign gout=gin[1]|(pin[1]&gin[0]);

endmodule // black

// Grey cell
module grey (gout, gin, pin);

   input logic [1:0] gin;
   input logic 	     pin;
   output logic      gout;

   assign gout=gin[1]|(pin&gin[0]);

endmodule // grey

// reduced Black cell
module rblk (hout, iout, gin, pin);

   input logic [1:0] gin, pin;
   output logic      hout, iout;

   assign iout=pin[1]&pin[0];
   assign hout=gin[1]|gin[0];

endmodule

// reduced Grey cell
module rgry (hout, gin);

   input logic [1:0] gin;
   output logic	     hout;

   assign hout=gin[1]|gin[0];

endmodule // rgry

module lz2 (P, V, B0, B1);

   input logic  B0;
   input logic 	B1;

   output logic P;
   output logic V;

   assign V = B0 | B1;
   assign P = B0 & ~B1;
   
endmodule // lz2

module lz4 (ZP, ZV, B0, B1, V0, V1);
   
   input logic        B0;
   input logic        B1;
   input logic        V0;
   input logic        V1;
   
   output logic [1:0] ZP;
   output logic       ZV;
   
   assign ZP[0] = V0 ? B0 : B1;
   assign ZP[1] = ~V0;
   assign ZV = V0 | V1;

endmodule // lz4

module lz8 (ZP, ZV, B);
   
   input logic [7:0]  B;

   logic 	      s1p0;
   logic 	      s1v0;
   logic 	      s1p1;
   logic 	      s1v1;
   logic 	      s2p0;
   logic 	      s2v0;
   logic 	      s2p1;
   logic 	      s2v1;
   logic [1:0] 	      ZPa;
   logic [1:0] 	      ZPb;
   logic 	      ZVa;
   logic 	      ZVb;
   
   output logic [2:0] ZP;
   output logic       ZV;
   
   lz2 l1(s1p0, s1v0, B[2], B[3]);
   lz2 l2(s1p1, s1v1, B[0], B[1]);
   lz4 l3(ZPa, ZVa, s1p0, s1p1, s1v0, s1v1);

   lz2 l4(s2p0, s2v0, B[6], B[7]);
   lz2 l5(s2p1, s2v1, B[4], B[5]);
   lz4 l6(ZPb, ZVb, s2p0, s2p1, s2v0, s2v1);

   assign ZP[1:0] = ZVb ? ZPb : ZPa;
   assign ZP[2]   = ~ZVb;
   assign ZV = ZVa | ZVb;

endmodule // lz8

module lz16 (ZP, ZV, B);

   input logic [15:0]  B;

   logic [2:0] 	       ZPa;
   logic [2:0] 	       ZPb;
   logic 	       ZVa;
   logic 	       ZVb;   

   output logic [3:0]  ZP;
   output logic        ZV;

   lz8 l1(ZPa, ZVa, B[7:0]);
   lz8 l2(ZPb, ZVb, B[15:8]);

   assign ZP[2:0] = ZVb ? ZPb : ZPa;
   assign ZP[3]   = ~ZVb;
   assign ZV = ZVa | ZVb;

endmodule // lz16

module lz32 (ZP, ZV, B);

   input logic [31:0] B;

   logic [3:0] 	      ZPa;
   logic [3:0] 	      ZPb;
   logic 	      ZVa;
   logic 	      ZVb;
   
   output logic [4:0] ZP;
   output logic       ZV;
   
   lz16 l1(ZPa, ZVa, B[15:0]);
   lz16 l2(ZPb, ZVb, B[31:16]);
   
   assign ZP[3:0] = ZVb ? ZPb : ZPa;
   assign ZP[4]   = ~ZVb;
   assign ZV = ZVa | ZVb;

endmodule // lz32

module fsm32 (en, state0, done, divdone, otfzero,
	      start, error, NumIter, clk, reset);

   input logic [4:0]  NumIter;   
   input logic 	      clk;
   input logic 	      reset;
   input logic 	      start;
   input logic 	      error;   
   
   output logic       done;      
   output logic       en;
   output logic       state0;
   output logic       divdone;
   output logic       otfzero;   
   
   logic 	      LT, EQ;
   logic 	      Divide0;   
   logic [4:0] 	      CURRENT_STATE;
   logic [4:0] 	      NEXT_STATE;   
   
   parameter [4:0] 
     S0=5'd0, S1=5'd1, S2=5'd2,
     S3=5'd3, S4=5'd4, S5=5'd5,
     S6=5'd6, S7=5'd7, S8=5'd8,
     S9=5'd9, S10=5'd10, S11=5'd11,
     S12=5'd12, S13=5'd13, S14=5'd14,
     S15=5'd15, S16=5'd16, S17=5'd17,
     S18=5'd18, Done=5'd31;      
   
   always @(posedge clk)
     begin
	if(reset==1'b1)
	  CURRENT_STATE<=S0;
	else
	  CURRENT_STATE<=NEXT_STATE;
     end

   // Going to cheat and hard code number of states 
   // needed into FSM instead of using a counter
   // FIXME: could counter be better

   // Cheated and made 8 - let synthesis do its magic
   magcompare8 comp1 (LT, EQ, {3'h0,CURRENT_STATE}, {3'h0,NumIter});

   always @(CURRENT_STATE or start)
     begin
 	case(CURRENT_STATE)
	  S0:
	    begin
	       if (start==1'b0)
		 begin
		    otfzero = 1'b1;   
		    en = 1'b0;
		    state0 = 1'b0;
		    divdone = 1'b0;		    
		    done = 1'b0;
		    NEXT_STATE <= S0;
		 end 
	       else 
		 begin
		    otfzero = 1'b0;	       		    
		    en = 1'b1;
		    state0 = 1'b1;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		    
		    done = 1'b0;
		    divdone = 1'b0;		 		 
		    NEXT_STATE <= S1;
		 end 
	    end	    
	  S1:
	    begin
	       otfzero = 1'b0;	       
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S2;
		 end
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S2;
		 end		    
	    end // case: S1	  
	  S2:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S3;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S3;
		 end		    	       	       
	    end // case: S2
	  S3:
	    begin	       
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S4;
		 end 
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S4;
		 end		    	       
	    end // case: S3
	  S4:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S5;
		 end 	       	    
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S5;
		 end		       	       
	    end // case: S4
	  S5:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S6;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S6;
		 end		    	       	       	       
	    end // case: S5
	  S6:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S7;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S7;
		 end		    	       	       
	    end // case: S6
	  S7:
	    begin
	       otfzero = 1'b0;	     
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S8;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S8;
		 end		    	       	       
	    end // case: S7
	  S8:
	    begin
	       otfzero = 1'b0;	     
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S9;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S9;
		 end		    	       	       
	    end // case: S8
	  S9:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S10;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S10;
		 end		    	       	       
	    end // case: S9
	  S10:
	    begin
	       otfzero = 1'b0;	      
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S11;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S11;
		 end		    	       	       
	    end // case: S10
	  S11:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S12;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S12;
		 end		    	       	       
	    end // case: S11
	  S12:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S13;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S13;
		 end		    	       	       
	    end // case: S12
	  S13:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S14;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S14;
		 end		    	       	       
	    end // case: S13
	  S14:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S15;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S15;
		 end		    	       	       
	    end // case: S14
	  S15:
	    begin
	       otfzero = 1'b0;
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S16;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S16;
		 end		    	       	       
	    end // case: S15
	  S16:
	    begin
	       otfzero = 1'b0;	       
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S17;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S17;
		 end		    	       	       
	    end // case: S16
	  S17:
	    begin
	       otfzero = 1'b0;	       
	       if (LT|EQ)
		 begin
		    en = 1'b1;
		    state0 = 1'b0;
		    done = 1'b0;
		    if (EQ)
		      divdone = 1'b1;		    
		    else
		      divdone = 1'b0;		 		 
		    NEXT_STATE <= S18;
		 end // if (LT|EQ)
	       else
		 begin
		    en = 1'b0;
		    state0 = 1'b0;
		    done = 1'b0;
		    divdone = 1'b0;
		    NEXT_STATE <= S18;
		 end		    	       	       
	    end // case: S16	  	  
	  S18:
	    begin
	       otfzero = 1'b1;	       	       	       
	       state0 = 1'b0;
	       done = 1'b1;
	       if (EQ)
		 begin
		    divdone = 1'b1;
		    en = 1'b1;
		 end
	       else
		 begin
		    divdone = 1'b0;
		    en = 1'b0;
		 end
	       NEXT_STATE <= S0;
	    end // case: S17
	  default: 
	    begin
	       otfzero = 1'b0;	       
	       en = 1'b0;
	       state0 = 1'b0;
	       done = 1'b0;
	       divdone = 1'b0;
	       NEXT_STATE <= S0;
	    end
	endcase // case(CURRENT_STATE)	
     end // always @ (CURRENT_STATE or X)   

endmodule // fsm32

// 2-bit magnitude comparator
// This module compares two 2-bit values A and B. LT is '1' if A < B 
// and GT is '1'if A > B. LT and GT are both '0' if A = B.

module magcompare2b (LT, GT, A, B);

   input logic [1:0]  A;
   input logic [1:0]  B;
   
   output logic       LT;
   output logic       GT;

   // Determine if A < B  using a minimized sum-of-products expression
   assign LT = ~A[1]&B[1] | ~A[1]&~A[0]&B[0] | ~A[0]&B[1]&B[0];
   // Determine if A > B  using a minimized sum-of-products expression
   assign GT = A[1]&~B[1] | A[1]&A[0]&~B[0] | A[0]&~B[1]&~B[0];

endmodule // magcompare2b

// J. E. Stine and M. J. Schulte, "A combined two's complement and
// floating-point comparator," 2005 IEEE International Symposium on
// Circuits and Systems, Kobe, 2005, pp. 89-92 Vol. 1. 
// doi: 10.1109/ISCAS.2005.1464531

module magcompare8 (LT, EQ, A, B);

   input logic [7:0]  A;
   input logic [7:0]  B;

   logic [3:0] 	      s;
   logic [3:0] 	      t;
   logic [1:0] 	      u;
   logic [1:0] 	      v;
   logic 	      GT;
   //wire 	LT;   
   
   output logic	      EQ;
   output logic       LT;   

   magcompare2b mag1 (s[0], t[0], A[1:0], B[1:0]);
   magcompare2b mag2 (s[1], t[1], A[3:2], B[3:2]);
   magcompare2b mag3 (s[2], t[2], A[5:4], B[5:4]);
   magcompare2b mag4 (s[3], t[3], A[7:6], B[7:6]);
   
   magcompare2b mag5 (u[0], v[0], t[1:0], s[1:0]);
   magcompare2b mag6 (u[1], v[1], t[3:2], s[3:2]);

   magcompare2b mag7 (LT, GT, v[1:0], u[1:0]);
   
   assign EQ = ~(GT | LT);   

endmodule // magcompare8