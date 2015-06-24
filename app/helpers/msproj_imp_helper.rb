
module MsprojImpHelper  
  def xml_resources resources
      resource = MsprojResource.new
      id = resources.elements['UID']
      resource.uid = id.text.to_i if id
      name = resources.elements['Name']
      resource.name = name.text if name
      return resource    
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
              task.priority_id = 4
      elsif priority < "500"
              task.priority_id = 3
      elsif priority < "750"
              task.priority_id = 5
      elsif priority < "1000"
              task.priority_id = 6
      else
              task.priority_id = 7
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
