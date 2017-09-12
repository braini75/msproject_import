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

    #raise issue.errors.full_messages.join(', ') unless issue.save
  end

  def xml_tasks tasks
      task = MsprojTask.new
      task.task_uid = tasks.elements['UID'].text.to_i if tasks.elements['UID']
      task.task_id = tasks.elements['ID'].text.to_i if tasks.elements['ID']
      task.wbs = tasks.elements['WBS'].text if tasks.elements['WBS']
      task.outline_level = tasks.elements['OutlineLevel'].text.to_i if tasks.elements['OutlineLevel']
      
      name = tasks.elements['Name']
      task.name = name.text if name
      
      start_date = tasks.elements['Start']
      task.start_date = start_date.text.split('T')[0] if start_date
      
      finish_date = tasks.elements['Finish']
      task.finish_date = finish_date.text.split('T')[0] if finish_date
      
      create_date = tasks.elements['CreateDate']
      date_time = create_date.text.split('T') if create_date
      task.create_date = date_time[0] + ' ' + date_time[1] if date_time
      
      # 'Work' is the total amount of work scheduled to be performed on a task by all assigned resources
      duration_arr = tasks.elements["Work"].text.split("H") if tasks.elements['Work']
      duration_hour = duration_arr[0][2..duration_arr[0].size-1] if duration_arr
      duration_min = duration_arr[1][0..duration_arr[1].index("M")-1] if duration_arr && duration_arr[1] && duration_arr[1].index("M")
      task.work = (duration_hour.to_f + duration_min.to_f/60).to_s if duration_arr
      
      # 'Duration' is the total span of active working time
      duration_arr = tasks.elements["Duration"].text.split("H") if tasks.elements['Duration']
      duration_hour = duration_arr[0][2..duration_arr[0].size-1] if duration_arr
      duration_min = duration_arr[1][0..duration_arr[1].index("M")-1] if duration_arr && duration_arr[1] && duration_arr[1].index("M")
      task.duration = (duration_hour.to_f + duration_min.to_f/60).to_s if duration_arr   
	  
      task.done_ratio = tasks.elements["PercentWorkComplete"].text if tasks.elements['PercentWorkComplete']          
      
      if tasks.elements['Priority']
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
      else
        task.priority_id = 2  #normal
      end
      task.notes=tasks.elements["Notes"].text if tasks.elements["Notes"]
      task.summary = tasks.elements["Summary"].text if tasks.elements["Summary"]
      
      logger.info("Task uID: #{task.task_uid}")
      tasks.each_element('PredecessorLink') do |link|
          predecessor=MsprojTaskPredecessor.new
          link_to=predecessor.init(link)
          logger.info("Link Predecessor: #{link_to.predecessor_uid}")
      end
	  
      return task
  end rescue raise 'parse error'
end
