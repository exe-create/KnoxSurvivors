-- Installed native action boundary only; production wrappers own permission.
ISGrabItemAction={}
function ISGrabItemAction:derive(name) return setmetatable({Type=name},{__index=self}) end
function ISGrabItemAction:new(character,object,time)
 local a=setmetatable({character=character,item=object,destContainer=character:getInventory(),maxTime=time},{__index=self})
 a:checkQueueList();return a
end
function ISGrabItemAction:isValid()
 local s=self.item:getSquare()
 return s~=nil and s:getWorldObjects():contains(self.item)
  and self.destContainer:hasRoomFor(self.character,self.item:getItem())
end
function ISGrabItemAction:transferItem(object)
 local item,square=object:getItem(),object:getSquare()
 square:getWorldObjects():remove(object);object.square=nil;item.world=nil
 (self.destContainer.AddItem or self.destContainer.add)(self.destContainer,item)
end
function ISGrabItemAction:perform()
 if self:isValid() then self:transferItem(self.item) end
 local q=ISTimedActionQueue.queues[self.character]
 if q then q:removeFromQueue(self);if q.current==self then q.current=q.queue[1] end end
end
function ISGrabItemAction:forceCancel() end
