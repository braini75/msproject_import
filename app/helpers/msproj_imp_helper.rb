
module MsprojImpHelper  
  def issue_deep(issue)
	  @cnt_deep=0
	  if issue.parent_id.nil?
		   return @cnt_deep
		else
		 parent=Issue.find(issue.parent_id)
		 @cnt_deep=1 + issue_deep(parent)
	  end
  end

  def xml_resources resources
      resource = MsprojResource.new
      id = resources.elements['UID']
      resource.uid = id.text.to_i if id
      name = resources.elements['Name']
      resource.name = name.text if name
      return resource    
  end
  
  def create_custom_fields
    IssueCustomField.create(:name => "MS Project WDS", :field_format => 'string') #Beispiel    
  end
  
  def update_custom_fields(issue, fields)
    f_id = Hash.new { |hash, key| hash[key] = nil }
    issue.available_custom_fields.each_with_index.map { |f,indx| f_id[f.name] = f.id }
    field_list = []
    fields.each do |name, value|
      field_id = f_id[name].to_s
      field_list << Hash[field_id, value]
    end
    issue.custom_field_values = field_list.reduce({},:merge)

    raise issue.errors.full_messages.join(', ') unless issue.save
  end

  def xml_tasks tasks
      task = MsprojTask.new
      task.task_id = tasks.elements['ID'].text.to_i
      task.wbs = tasks.elements['WBS'].text
#      task.outline_number = tasks.elements['OutlineNumber'].text
      task.outline_level = tasks.elements['OutlineLevel'].text.to_i
      
      name = tasks.elements['Name']
      task.name = name.text if name
      date = Date.new
      start_date = tasks.elements['Start']
      task.start_date = start_date.text.split('T')[0] if start_date
      
      finish_date = tasks.elements['Finish']
      task.finish_date = finish_date.text.split('T')[0] if finish_date
      
      create_date = tasks.elements['CreateDate']
      date_time = create_date.text.split('T')
      task.create_date = date_time[0] + ' ' + date_time[1] if start_date
      #task.create = name ? !(has_task(name.text)) : true
      duration_arr = tasks.elements["Duration"].text.split("H")
      task.duration = duration_arr[0][2..duration_arr[0].size-1]         
      task.done_ratio = tasks.elements["PercentComplete"].text          
      task.outline_level = tasks.elements["OutlineLevel"].text.to_i  
      priority = tasks.elements["Priority"].text
      if priority == "500"
              task.priority_id = 2  #normal
      elsif priority < "500"
              task.priority_id = 1  #niedrig
      elsif priority < "750"
              task.priority_id = 3  #hoch
      elsif priority < "1000"
              task.priority_id = 4  #dringend
      else
              task.priority_id = 5  #sofort
      end   
      task.notes=tasks.elements["Notes"].text if tasks.elements["Notes"]
    return task
  end rescue raise 'parse error'
  
  private
  def has_task name, issues
    issues.each do |issue|
      return true if issue.subject == name
    end
    false
  end
end
