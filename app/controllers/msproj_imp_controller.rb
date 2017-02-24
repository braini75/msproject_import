class MsprojImpController < ApplicationController
  unloadable
  require 'rexml/document'
  require 'date'
  
  before_filter :find_project, :only => [:analyze, :upload, :import_results]
  before_filter :init_cache, :only => [:analyze, :upload, :import_results]
  before_filter :read_cache, :only => [:import_results, :status]
  after_filter  :write_cache, :only => [:analyze]
  after_filter :clear_flash
  
  include MsprojImpHelper      
  
  def upload
	
  end 
  
  def import_results
	if params[:do_import].nil?
          redirect_to :action => 'upload'
        else
		  @add_IssueSuffix = params[:add_IssueSuffix]
		  @add_wbs2name = params[:add_wbs2name]
		  
          @root_task = import
		  @@cache.clear
    end
  end

  def analyze
    flash.clear
	
	@filepath = MsprojDataFile.save(params[:upload])
    
    @resources  = []
    @tasks      = []
    @assignments= []
    @required_custom_fields=[]
	@predecessor_link = []
	@usermapping = []	
	
	content = MsprojDataFile.content
    
      doc     = REXML::Document.new(content)
                 
      @prefix="MS Project Import(#{Date.today}): "

      
      doc.elements.each('Project') do |ele|
        
        if ele.elements["Title"].nil?          
          session[:title] = "MSProjectImport_#{User.current}:#{Date.today}"
          flash[:warning] = "No Titel in XML found. I use #{@title} instead!"
          #@title = ele.elements["Name"].text if ele.elements["Name"] 
        else
          session[:title] = @prefix + ele.elements["Title"].text
        end
		

      ele.each_element('//Resource') do |child|
        @resources.push(xml_resources child)
      end
      
      logger.info "Ressource passed!"
      
      resource_uids = []
      ele.each_element('//Assignment') do |child|
        assign = MsprojAssignment.new(child)
        if assign.resource_uid >= 0
          resource_uids.push(assign.resource_uid) 
          @assignments.push(assign)
        end         
      end
      
      logger.info "Assignment passed!"
      
      
      
      @member_uids = @project.members.map { |x| x.user_id}
      
      resource_uids.uniq.each do |resource_uid|
        resource = @resources.select { |res| res.uid == resource_uid }.first
        
        unless resource.nil?
          user = resource.map_user(@member_uids)
          #logger.info("Name: #{resource.name} Res_ID #{resource_uid} USER: #{user}")
          #logger.info("\n -----------INFO: #{resource.info} Status: #{resource.status}")
          unless user.nil?             
            @usermapping.push([resource_uid,resource.name, user, resource.status])
          end
        end
        #logger.debug("Mapping Resource: #{resource} UserMapping: #{@usermapping}")
        @no_mapping_found=@usermapping.select { |id, name, user_obj, status| status.to_i > 2}.count
        unless @no_mapping_found == 0
          flash[:error] = "Error: #{l(:no_failed_mapping, @no_mapping_found)}"  
        end
      end
            
      # check for required custom_fields in current project
      @project.all_issue_custom_fields.each do |custom_field|
        if custom_field.is_required
          flash[:warning] = "Required custom field #{custom_field.name} found. We will set them to 'n.a'"
          @required_custom_fields.push([custom_field.name,'n.a.'])
        end
      end

	  @task_skipped = ""
      ele.each_element('//Task') do |child|	
		if child.elements['IsNull'].text == "0" && child.elements['Name']
			task_uid = child.elements['UID'].text.to_i if child.elements['UID']		
			#logger.info("Task uID: #{task_uid}")
			child.each_element('PredecessorLink') do |link|
				predecessor=MsprojTaskPredecessor.new
				link_to=predecessor.init(link)
				link_to.issue_from_id=task_uid
				@predecessor_link.push link_to
				#logger.info("Link Predecessor: #{@predecessor_link.last}")
			end
			@tasks.push(xml_tasks child)
		else			
			logger.info ("Skipping IsNull-Task and Task without NAME!")
			@task_skipped += child.elements['ID'].text + " "
		end
    
	   end
      
      logger.info "Task passed!"
	  
      end 
		
      extra_info = ""
	  extra_info = "<br>Following empty tasks skipped: " + @task_skipped + "!" unless @task_skipped.blank?
	  flash[:notice] = "Project parsed" + extra_info #if flash.empty?

  end
  
  private
  def clear_flash
	flash.clear
  end
  
  def init_cache
	tmp_path = Rails.root.join('tmp')
	unless File.writable? tmp_path.to_s
		flash[:error] = "Temp-Dir: '" + tmp_path.to_s + "' is not writable!"
	end
	@@cache = ActiveSupport::Cache::FileStore.new(Rails.root.join('tmp','msproj_imp').to_s)
  end
  
  def read_cache
	@resources  = @@cache.read(:resources)
    @tasks      = @@cache.read(:tasks)
    @assignments= @@cache.read(:assignments)
    @required_custom_fields = @@cache.read(:required_custom_fields)
	@predecessor_link = @@cache.read(:predecessor_link)
	@usermapping = @@cache.read(:usermapping)
  end
  
  def write_cache
    @@cache.write(:resources, @resources)
	@@cache.write(:tasks, @tasks)
	@@cache.write(:assignments, @assignments)
	@@cache.write(:required_custom_fields, @required_custom_fields)
	@@cache.write(:predecessor_link, @predecessor_link)
	@@cache.write(:usermapping, @usermapping)
  end
  
  def import
    logger.info "Start Import..." 
	
	@errorMessages = "";
    
    last_task_uid = 0
    parent_id = 0
    root_task_uid = 0
    last_outline_level = 0
    parent_stack = Array.new #contains a LIFO-stack of parent task
	
	errorMsg =""
	mapUID2IssueID=[] # maps UIDs to redmine issue_id
        
    @tasks.each do |task|	
      issue = Issue.new(
        :author   => User.current,
        :project  => @project
        )
      issue.status_id = 1   # 1-neu
      issue.tracker_id = Setting.plugin_msproject_import['tracker_default']  # 1-Bug, 2-Feature...
      
      if task.task_uid > 0
		subject = ""
		subject = @add_IssueSuffix + " " if @add_IssueSuffix
		subject = subject + task.wbs + " " if @add_wbs2name 

		issue.subject = subject + task.name
		
        assign=@assignments.select{|as| as.task_uid == task.task_uid}.first
        unless assign.nil? 
          logger.info("Assign: #{assign}")
          mapped_user=@usermapping.select { |id, name, user_obj, status| id == assign.resource_uid and status < 3}.first
          logger.info("Mapped User: #{mapped_user}")
          issue.assigned_to_id  = mapped_user[2].id unless mapped_user.nil?          
        end
      else
        issue.subject = session[:title]	
      end

      issue.start_date = task.start_date
      issue.due_date = task.finish_date
      issue.updated_on = task.create_date
      issue.created_on = task.create_date
      issue.estimated_hours = task.duration
      issue.priority_id = task.priority_id
      issue.done_ratio = task.done_ratio     
      issue.description = task.notes

      # subtask?            
      if task.outline_level > 0
        issue.root_id = root_task_uid
        if task.outline_level > last_outline_level # new subtask
          parent_id = last_task_uid           
          parent_stack.push(parent_id)          
        end

        if task.outline_level < last_outline_level # step back in hierarchy
          steps=last_outline_level-task.outline_level
          parent_stack.pop(steps)  
          parent_id=parent_stack.last
        end 
        
        issue.parent_id = parent_id 
      end
      
      last_outline_level = task.outline_level
      
      # required custom fields:
      update_custom_fields(issue, @required_custom_fields)
                        
      if issue.save   
		mapUID2IssueID[task.task_uid]= issue.id
        last_task_uid = issue.id
        root_task_uid = issue.id if task.outline_level == 0
        logger.info "New issue #{issue.subject} in Project: #{@project} created!" 
        flash[:notice] = "Project successful inserted!"        
      else
        errorMsg = "Issue #{task.name} Task #{task.task_id} gives Error: #{issue.errors.full_messages}"
		logger.info errorMsg
		@errorMessages += errorMsg + "<br>"
        
      end	  			   
  end 
  # any relations?
  @predecessor_link.each do |link|	    
		relation = IssueRelation.new
#		logger.info "Link Info #{link} from_id: #{link.issue_from_id}"
		relation.issue_from_id = mapUID2IssueID[link.issue_from_id]
		relation.issue_to_id = mapUID2IssueID[link.issue_to_id]
		relation.relation_type = "follows"
		relation.delay = link.link_lag
		if relation.save
			logger.info "Issue linked to Predecessor: #{relation.issue_to_id}"
		else						
			errorMsg = "Error linking Task #{link.issue_from_id} to #{link.issue_to_id}! More Info:  #{relation.errors.messages}"
			logger.info errorMsg
			@errorMessages += errorMsg + "<br>"
	    end           		    
  end
  
  
  flash[:error] = @errorMessages unless @errorMessages.blank?
  return root_task_uid.to_i
  end
    
  
  def find_project
    @project = Project.find(params[:project_id])
  end
end