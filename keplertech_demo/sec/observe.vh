// Observation layer, included by both wrappers.
// Expects: oe_raw, dout_raw[3:0] (active-high core bus outputs) and
//          env_ph / env_ph_valid (phase recovered from the design's own sync).
// `MASK_X1`: the data bus (bus_oe and bus_d) is not observed during X1.
`ifdef MASK_X1
wire obs_mask = env_ph_valid & (env_ph == 3'd5);
`else
wire obs_mask = 1'b0;
`endif
assign bus_oe = oe_raw & ~obs_mask;
assign bus_d  = bus_oe ? dout_raw : 4'd0;
