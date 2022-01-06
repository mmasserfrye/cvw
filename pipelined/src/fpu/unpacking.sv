module unpacking ( 
    input logic  [63:0] X, Y, Z,
    input logic         FmtE,
    input logic  [2:0]  FOpCtrlE,
    output logic        XSgnE, YSgnE, ZSgnE,
    output logic [10:0] XExpE, YExpE, ZExpE,
    output logic [52:0] XManE, YManE, ZManE,
    output logic XNormE,
    output logic XNaNE, YNaNE, ZNaNE,
    output logic XSNaNE, YSNaNE, ZSNaNE,
    output logic XDenormE, YDenormE, ZDenormE,
    output logic XZeroE, YZeroE, ZZeroE,
    output logic [10:0] BiasE,
    output logic XInfE, YInfE, ZInfE,
    output logic XExpMaxE
);
 
    logic [51:0]    XFracE, YFracE, ZFracE;
    logic           XExpNonzero, YExpNonzero, ZExpNonzero;
    logic           XFracZero, YFracZero, ZFracZero; // input fraction zero
    logic           XExpZero, YExpZero, ZExpZero; // input exponent zero
    logic           YExpMaxE, ZExpMaxE;  // input exponent all 1s
    logic           XDoubleNaN, YDoubleNaN, ZDoubleNaN;

    // Determine if number is NaN as double precision to check single precision NaN boxing
    assign XDoubleNaN = &X[62:52] & |X[51:0]; 
    assign YDoubleNaN = &Y[62:52] & |Y[51:0]; 
    assign ZDoubleNaN = &Z[62:52] & |Z[51:0]; 

    assign XSgnE = FmtE ? X[63] : X[31];
    assign YSgnE = FmtE ? Y[63] : Y[31];
    assign ZSgnE = FmtE ? Z[63] : Z[31];

    assign XExpE = FmtE ? X[62:52] : {X[30], {3{~X[30]&~XExpZero|XExpMaxE}}, X[29:23]}; 
    assign YExpE = FmtE ? Y[62:52] : {Y[30], {3{~Y[30]&~YExpZero|YExpMaxE}}, Y[29:23]}; 
    assign ZExpE = FmtE ? Z[62:52] : {Z[30], {3{~Z[30]&~ZExpZero|ZExpMaxE}}, Z[29:23]}; 

    assign XFracE = FmtE ? X[51:0] : {X[22:0], 29'b0};
    assign YFracE = FmtE ? Y[51:0] : {Y[22:0], 29'b0};
    assign ZFracE = FmtE ? Z[51:0] : {Z[22:0], 29'b0};

    assign XExpNonzero = FmtE ? |X[62:52] : |X[30:23]; 
    assign YExpNonzero = FmtE ? |Y[62:52] : |Y[30:23];
    assign ZExpNonzero = FmtE ? |Z[62:52] : |Z[30:23];

    assign XExpZero = ~XExpNonzero;
    assign YExpZero = ~YExpNonzero;
    assign ZExpZero = ~ZExpNonzero;
   
    assign XFracZero = ~|XFracE;
    assign YFracZero = ~|YFracE;
    assign ZFracZero = ~|ZFracE;

    assign XManE = {XExpNonzero, XFracE};
    assign YManE = {YExpNonzero, YFracE};
    assign ZManE = {ZExpNonzero, ZFracE};

    assign XExpMaxE = FmtE ? &X[62:52] : &X[30:23];
    assign YExpMaxE = FmtE ? &Y[62:52] : &Y[30:23];
    assign ZExpMaxE = FmtE ? &Z[62:52] : &Z[30:23];
  
    assign XNormE = ~(XExpMaxE|XExpZero);
    
    // force single precision input to be a NaN if it isn't properly Nan Boxed
    assign XNaNE = XExpMaxE & ~XFracZero | ~FmtE & ~XDoubleNan;
    assign YNaNE = YExpMaxE & ~YFracZero | ~FmtE & ~YDoubleNan;
    assign ZNaNE = ZExpMaxE & ~ZFracZero | ~FmtE & ~ZDoubleNan;

    assign XSNaNE = XNaNE&~XFracE[51];
    assign YSNaNE = YNaNE&~YFracE[51];
    assign ZSNaNE = ZNaNE&~ZFracE[51];

    assign XDenormE = XExpZero & ~XFracZero;
    assign YDenormE = YExpZero & ~YFracZero;
    assign ZDenormE = ZExpZero & ~ZFracZero;

    assign XInfE = XExpMaxE & XFracZero;
    assign YInfE = YExpMaxE & YFracZero;
    assign ZInfE = ZExpMaxE & ZFracZero;

    assign XZeroE = XExpZero & XFracZero;
    assign YZeroE = YExpZero & YFracZero;
    assign ZZeroE = ZExpZero & ZFracZero;

    assign BiasE = 11'h3ff; // always use 1023 because exponents are unpacked to double precision

endmodule