local calls=0
local bridge={getNpcRecordLocation=function(_,record)
    calls=calls+1
    local x=record=="moved-record" and 25.9 or (record=="invalid-record" and (0/0) or 10.9)
    return {get=function(_,key) return key=="x" and x or (key=="y" and -2.1 or 1) end}
end}
for i=1,200 do
    local x,y,z,err=codecRecordLocation(bridge,"unchanged-record")
    assert(x==10 and y==-3 and z==1 and err==nil)
end
assert(calls==1,"unchanged portable record needs only one XYZ decode across repeated scans")
assert(codecRecordLocation(bridge,"moved-record")==25 and calls==2,"changed record invalidates coordinates")
for i=1,2 do
    local x,_,_,err=codecRecordLocation(bridge,"invalid-record")
    assert(x==nil and err=="record_location_unavailable")
end
assert(calls==4,"invalid decodes are not cached as successful locations")
local other={getNpcRecordLocation=function() return {get=function() return 99 end} end}
assert(codecRecordLocation(other,"unchanged-record")==99,"bridge replacement cannot reuse another parser's result")
assert(codecRecordLocation(bridge,"unchanged-record")==10 and calls==5)
assert(codecRecordLocation(nil,"unchanged-record")==nil,"missing bridge remains an explicit failure")
codecRecordLocation(bridge,"bounded-first")
for i=1,256 do codecRecordLocation(bridge,"bounded-"..tostring(i)) end
local before=calls
codecRecordLocation(bridge,"bounded-first")
assert(calls==before+1,"transient parse cache evicts old entries independently of global population")
print("Record location cache PASS repeated_decodes=1 changed_record=true bad_result_uncached=true bridge_identity=true bounded_256=true native_frame_time=false")
