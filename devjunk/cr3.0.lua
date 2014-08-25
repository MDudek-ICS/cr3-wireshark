--
-- lol
--

cr3_proto = Proto("cr3.0","Crimson v3 dev 0")

-- define the field names, widths, descriptions, and number base
-- looks like lua structs is what I should use here
local pf_payload_length = ProtoField.uint16("cr3.len", "Length", base.HEX)
local pf_reg = ProtoField.uint16("cr3.reg", "Register number", base.HEX)
local pf_payload = ProtoField.bytes("cr3.payload", "Payload")
local ptype = ProtoField.uint16("cr3.payload.type", "Type", base.HEX)
local pzero = ProtoField.uint16("cr3.payload.zero", "Zero", base.HEX)

local prest = ProtoField.bytes("cr3.payload.rest", "Data")
local pstring = ProtoField.string("cr3.payload.string", "String")

-- example I followed said not to do the fields like this, risk of missing some
cr3_proto.fields = {
	pf_payload_length,
	pf_reg,
	pf_payload,
	ptype,
	pstring
}

-- trying out a global variable for processing any cr3 segments
local processing_segment = false
local reassembled_length = 0
local segment_cur = 0 
local segment_data = nil

function cr3_proto.dissector(tvbuf,pinfo,tree)

	print(string.format("cr3_proto.dissector called, processing_segment = %s", processing_segment))
	-- set the protocol column based on the Proto object
	pinfo.cols.protocol = cr3_proto.description
	
	-- length of the entire CR3 payload
	local pktlen = tvbuf:reported_length_remaining()
	
	if not processing_segment then
	
		-- define this entire length as the object of dissection
		local subtree = tree:add(cr3_proto, tvbuf:range(0, pktlen))
		
		-- setup fields in the proper order and width
		local offset = 0
		
		local cr3len = tvbuf(offset,2):uint()
		subtree:add(pf_payload_length,tvbuf(offset,2))
		offset = offset + 2
		
		local reg = tvbuf(offset,2):uint()
		subtree:add(pf_reg, reg)
		offset = offset + 2
	
		-- payload gets broken out
		-- this pattern feels buggy
		local payloadtree = subtree:add(pf_payload, tvbuf:range(offset, pktlen - offset))
		payloadtree:append_text(string.format(" (0x%02x bytes)", tvbuf:reported_length_remaining() - 4))
	
		payloadtree:add(ptype, tvbuf(offset, 2))
		local packettype = tvbuf:range(offset, 2):uint()
		offset = offset + 2
	
		print(string.format("pktlen 0x%04x, cr3len 0x%04x, reg 0x%04x", pktlen, cr3len, reg))
		
		-- every place a packettype is checked, check to make sure ! processing_segment
		-- other wise a bug may happen with the processing of messages 
		-- // Sun Jul 27 14:19:41 CDT 2014 - ++TODO: LOOK FOR THIS BUG IN THE HANDLING OF SEGMENTS
		if (packettype == 0x0300 and ( reg == 0x012a or reg == 0x012b)) then
			string = tvbuf:range(offset):stringz()
			payloadtree:add(pstring, string)
		elseif packettype == 0x1500 and (cr3len - pktlen > 2) then 
			processing_segment = true
	
			pinfo.desegment_len = cr3len
			reassembled_length = cr3len
			segment_data = tvbuf:range(offset):string()
			print(string.format("CR3 segmentation detected, pinfo.desegment_len = 0x%04x, reassembled_length = 0x%04x, pktlen = 0x%04x", pinfo.desegment_len, reassembled_length, pktlen))
			return
		end

	-- handle CR3 segmentation
	-- packettype 0x1500 sets the flag
	-- 
	elseif processing_segment then
		print(string.format("    continuing desegmentation, pinfo.desegment_len = 0x%04x, reassembled_length = 0x%04x, pktlen = 0x%04x", pinfo.desegment_len, reassembled_length, pktlen))
		pinfo.desegment_len = pinfo.desegment_len + pktlen
		segment_data[#segment_data+1] = tvbuf:range(0, pktlen):string{}

		if pinfo.desegment_len >= reassembled_length then
			processing_segment = false
			payloadtree:add(tvbuff:range(0, pinfo.desegment_len))
			pinfo.desegment_len = 0
			print "CR3 segment ended"
		end
		
		return
	end

	puts "After segment processing code"

	-- if offset < pktlen then 
	-- 	payloadtree:add(prest, tvbuf:range(offset, pktlen-offset))
	-- 	offset = offset + 2
	-- end

	-- setting CR3 summary data into the info column in the UI
	pinfo.cols.info = string.format("Register: 0x%04x, Type: 0x%04x", reg, packettype)

	-- debug
	print(string.format("Register: 0x%04x, Type: 0x%04x", reg, packettype))
	print(string.format("pktlen 0x%04x, cr3.length 0x%04x", pktlen, cr3len))

	print("\n")
end

-- load the tcp.port table
tcp_table = DissectorTable.get("tcp.port")
-- register our protocol tcp:789
tcp_table:add(789,cr3_proto)
print("Wireshark version = ", get_version())
