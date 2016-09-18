class MsprojTaskPredecessor
  attr_accessor :issue_from_id
  attr_accessor :predecessor_uid
  attr_accessor :type 				# 0 = FF(finish2finish, 1 = FS(finish2start), 2 = SF (Start2Finish), 3 = Start2Start  
  attr_accessor :cross_project		# Indicates whether the task predecessor is part of another project
  attr_accessor :link_lag			# Amount of lag time
  attr_accessor :lag_format			# Lag in DurationFormat (3 = minutes, 5 = stunden, 7=tage, 9=wochen, 11=months) default =7
  
  def issue_to_id
	return self.predecessor_uid
  end
  
  def init(link)		# funktioniert gar nicht!!!
	self.predecessor_uid = link.elements["PredecessorUID"].text.to_i unless link.elements["PredecessorUID"].nil?
	self.type = link.elements["Type"].text.to_i unless link.elements["Type"].nil?
	self.cross_project = link.elements["CrossProject"].text.to_i unless link.elements["CrossProject"].nil?
	self.link_lag = link.elements["LinkLag"].text.to_i unless link.elements["LinkLag"].nil?
	self.lag_format = link.elements["LagFormat"].text.to_i unless link.elements["LagFormat"].nil?	
	return 	self
  end
end