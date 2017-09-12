class MsprojAssignment
  attr_accessor :assignment_id
  attr_accessor :task_uid
  attr_accessor :resource_uid
  attr_accessor :units
  
  def initialize(xml_assign)    
    self.assignment_id  = xml_assign.elements['UID'].text.to_i if xml_assign.elements['UID'] 
    self.task_uid       = xml_assign.elements['TaskUID'].text.to_i if xml_assign.elements['TaskUID'] 
    self.resource_uid   = xml_assign.elements['ResourceUID'].text.to_i if xml_assign.elements['ResourceUID']
	self.units			= xml_assign.elements['Units'].text.to_d if xml_assign.elements['Units']
  end
  
end