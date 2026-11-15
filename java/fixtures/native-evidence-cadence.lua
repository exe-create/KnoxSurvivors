local old=KnoxSettings;local enabled=false;local calls=0;local opted=false
KnoxSettings={showDeveloperDiagnostics=function() return enabled end}
local c={status=function(_,include) calls=calls+1;opted=include;return 'fixture' end}
local bridge={getRenderDiagnostics=function() return 'fixture' end}
nativeEvidenceCadence(300,bridge,{id=c},{'id'});nativeEvidenceCadence(1,bridge,{id=c},{'id'});assert(calls==0,'diagnostics disabled does not sample')
enabled=true;nativeEvidenceCadence(1,bridge,{id=c},{'id'});assert(calls==0,'diagnostics preserves existing cadence')
nativeEvidenceCadence(300,bridge,{id=c},{'id'});assert(calls==1 and opted==true,'diagnostic cadence opts into evidence once')
KnoxSettings=old
