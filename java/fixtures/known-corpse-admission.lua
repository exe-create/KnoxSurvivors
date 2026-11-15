local calls=0
local c={baseTaskCorpsePhase='grab',reportKnownCorpse=function() calls=calls+1 end,failBaseTaskAction=function(self) self.failed=true end}
corpseAdmission(c,nil,'refused',{},1);assert(c.failed and calls==0,'refused grab gives no recognition')
c.failed=false;corpseAdmission(c,{},nil,{},2);assert(c.baseTaskActionQueued and calls==1,'admitted grab reports once')
c.baseTaskCorpsePhase='drop';corpseAdmission(c,{},nil,{},3);assert(calls==1,'drop gives no recognition')
c.baseTaskCorpsePhase='grab';c.reportKnownCorpse=function() error('fixture callback') end
assert(corpseAdmission(c,{},nil,{},4) and c.baseTaskActionQueued,'callback failure preserves admission')
