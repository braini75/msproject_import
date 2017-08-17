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
  include PlusganttUtilsHelper
  
  def upload
	if @utils.nil?
		@utils = Utils.new()
	end
	@parent_issue = @utils.get_issue_project_parent(@project)
	if @parent_issue.nil?
		@parent_issue_text = l(:label_not_not_found)
	else
		@parent_issue_text = "#" + @parent_issue.id.to_s + " - " + @parent_issue.subject
	end
  end 
  
  def import_results
	if params[:do_import].nil?
        redirect_to :action => 'upload'
    else
		@add_IssueSuffix = params[:add_IssueSuffix]
		@add_wbs2name = params[:add_wbs2name]
		import_result = []
		if params[:erase_issues]
			begin
				Issue.transaction do
					Rails.logger.info("----------------------DELETING ISSUES-------------------")
					issues = Issue.select(:id).order(id: :desc).where("project_id = ?", @project.id).to_a || []
					Issue.destroy(issues)
					@project.issues.clear
					Rails.logger.info("----------------------ALL ISSUES WERE DELETED------------------")
					import_result = import
					Rails.logger.info("----------------------FINISH IMPORT------------------")
					@project.issues.reload
					Rails.logger.info("----------------------ISSUES RELOADED------------------")
				end
			rescue => exception
				Rails.logger.info("---------------------EXCEPCION------------------------------")
				flash[:error] = "Error: " + "#{exception.class}: #{exception.exception}"
				render :action => 'upload'
				return
			end
		else
			Rails.logger.info("No issues were deleted")
			if @utils.nil?
				@utils = Utils.new()
			end
			@parent_issue = @utils.get_issue_project_parent(@project)
			import_result = import(@parent_issue)
			@project.issues.reload
		end
        
		@issues_imported = import_result[:issues_imported]
		if @issues_imported > 0
			if import_result[:new_parent_created].nil?
				if @parent_issue.nil?
					@root_task = 0
				else
					@root_task = @parent_issue.id
				end
			else
				@root_task = import_result[:new_parent_created]
			end
		end
		@@cache.clear
    end
  end

  def analyze
	@filepath = MsprojDataFile.save(params[:upload]) 
    @resources  = []
    @tasks      = []
    @assignments= []
    @required_custom_fields=[]
	@predecessor_link = []
	@usermapping = []
	project_parent_issue = false
	warning = ''
	error = ''
	content = MsprojDataFile.content
	doc     = REXML::Document.new(content) 
	@prefix="MS Project Import(#{Date.today}): "

	flash.clear
	
    doc.elements.each('Project') do |ele|    
		if ele.elements["Title"].nil?          
			if ele.elements["Name"].nil?
				session[:title] = "MSProjectImport_#{User.current}:#{Date.today}"
			else
				session[:title] = @prefix + ele.elements["Name"].text
			end
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
				unless user.nil?             
					@usermapping.push([resource_uid, resource.name, user, resource.status])
				end
			end
		end
		@no_mapping_found=@usermapping.select { |id, name, user_obj, status| status.to_i > 2}
		if @no_mapping_found.count > 0
			if warning != ''
				warning = warning + "<br>#{l(:users_not_found)}"
			else
				warning = "#{l(:users_not_found)}"
			end
		end
		@no_mapping_found.each do |ele|
			warning = warning + "'" + ele[1] + "' "
		end
            
		# check for required custom_fields in current project
		@project.all_issue_custom_fields.each do |custom_field|
			if custom_field.is_required
				if warning != ''
					warning = warning + "<br>" + "Required custom field #{custom_field.name} found. We will set them to 'n.a'"
				else
					warning = "Required custom field #{custom_field.name} found. We will set them to 'n.a'"
				end
				@required_custom_fields.push([custom_field.name,'n.a.'])
			end
		end

		@task_skipped = ""
		ele.each_element('//Task') do |child|	
			if child.elements['IsNull'].text == "0" && child.elements['Name']
				task_uid = child.elements['UID'].text.to_i if child.elements['UID']		
				child.each_element('PredecessorLink') do |link|
					predecessor=MsprojTaskPredecessor.new
					link_to=predecessor.init(link)
					link_to.issue_from_id=task_uid
					@predecessor_link.push link_to
				end
				@tasks.push(xml_tasks child)
				if child.elements['OutlineLevel'].text == '0'
					project_parent_issue = true
				end
			else			
				@task_skipped += child.elements['ID'].text + " "
				if child.elements['OutlineLevel'].text == '0'
					if error != ''
						error = error + "<br>" + "No project parent task was found."
					else
						error = "No project parent task was found."
					end
				end
			end
		end
		logger.info "Task passed!"
    end

	if !project_parent_issue
		flash[:error] = error
		flash[:warning] = warning
		render :action => 'upload'
	else
		extra_info = ""
		extra_info = "<br>Following empty tasks skipped: " + @task_skipped + "!" unless @task_skipped.blank?
		flash[:notice] = "Project parsed" + extra_info 
		flash[:warning] = warning
	end
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
  
  def import(parent_issue=nil)
    logger.info "Start Import..." 
	@errorMessages = "";
    new_parent_created = 0
    last_task_uid = 0
	if parent_issue.nil?
		parent_id = 0
		root_task_uid = 0
	else
		Rails.logger.info("Setting parent and root to: " + parent_issue.id.to_s)
		parent_id = parent_issue.id
		root_task_uid = parent_issue.id
	end
    last_outline_level = 0
    parent_stack = Array.new #contains a LIFO-stack of parent task
	errorMsg =""
	mapUID2IssueID=[] # maps UIDs to redmine issue_id
	issues_imported = 0
        
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
          if mapped_user.nil?
			#Find manually asignment
			if params['map_user_to_' + assign.resource_uid.to_s] && !params['map_user_to_' + assign.resource_uid.to_s].blank?
				logger.info("setting asignment: " + params['map_user_to_' + assign.resource_uid.to_s])
				issue.assigned_to_id = params['map_user_to_' + assign.resource_uid.to_s].to_i
			end
		  else
			issue.assigned_to_id  = mapped_user[2].id
		  end
		  if issue.project.module_enabled?("plusgantt") && CustomField.find_by_name_and_type('asignacion', 'IssueCustomField') && assign.units && assign.units.to_d != 1.0
			asignment = (Plusgantt.hour_by_day * assign.units).round(2)
			logger.info("asignment: " + asignment.to_s)
			field_list = []
			field_list << Hash[CustomField.find_by_name_and_type('asignacion', 'IssueCustomField').id, asignment]
			issue.custom_field_values = field_list.reduce({},:merge)
		  end
        end
      else
        issue.subject = task.name	
      end

      issue.updated_on = task.create_date
      issue.created_on = task.create_date
      issue.priority_id = task.priority_id
 
      issue.description = task.notes

      # subtask?            
      if task.outline_level > 0
        issue.root_id = root_task_uid
        if task.outline_level > last_outline_level # new subtask
          if last_task_uid > 0
			parent_id = last_task_uid        
			parent_stack.push(parent_id)
		  end
        end

        if task.outline_level < last_outline_level # step back in hierarchy
          steps=last_outline_level-task.outline_level
          parent_stack.pop(steps)  
          parent_id=parent_stack.last
        end 
        if !parent_id.nil? && parent_id > 0
			issue.parent_id = parent_id
		end
	  else
		if !parent_id.nil? && parent_id > 0
			issue.parent_id = parent_id
		end
		if !root_task_uid.nil? && root_task_uid > 0
			issue.root_id = root_task_uid
		end
      end
      
      last_outline_level = task.outline_level
      
      # required custom fields:
      update_custom_fields(issue, @required_custom_fields)
	  
	  if MsprojectImport.import_summary
		if MsprojectImport.use_work
			issue.estimated_hours = task.work
		else
			issue.estimated_hours = task.duration
		end
		issue.done_ratio = task.done_ratio    
		issue.start_date = task.start_date
		issue.due_date = task.finish_date
	  else
		if task.summary == '0'
			if MsprojectImport.use_work
				issue.estimated_hours = task.work
			else
				issue.estimated_hours = task.duration
			end
			issue.done_ratio = task.done_ratio    
			issue.start_date = task.start_date
			issue.due_date = task.finish_date
		  end
	  end
                        
      if issue.save   
		mapUID2IssueID[task.task_uid]= issue.id
        last_task_uid = issue.id
		if root_task_uid.nil? || root_task_uid == 0
			root_task_uid = issue.id
		end
		if new_parent_created.nil? || new_parent_created == 0
			new_parent_created = issue.id
		end
        logger.info "New issue #{issue.subject} in Project: #{@project} created!"     
		issues_imported	+= 1
      else
        errorMsg = "Issue #{task.name} Task #{task.task_id} gives Error: #{issue.errors.full_messages}"
		logger.info errorMsg
		@errorMessages += errorMsg + "<br>"
      end	  			   
  end
  
  if last_task_uid > 0
	#Verify
	  @predecessor_link.each do |link|	    
			relation = IssueRelation.new
	#		logger.info "Link Info #{link} from_id: #{link.issue_from_id}"
			relation.issue_from_id = mapUID2IssueID[link.issue_from_id]
			relation.issue_to_id = mapUID2IssueID[link.issue_to_id]
			relation.relation_type = "follows"
			case link.lag_format
				when 7
					logger.info "link_lag - " + link.link_lag.to_s
					#If lag format is 7 then amount of lag in tenths of a minute.
					relation.delay = (link.link_lag / 4800)
				else
					logger.info "lag format - " + link.lag_format.to_s
					relation.delay = link.link_lag
			end
			
			if relation.save
				logger.info "Issue linked to Predecessor: #{relation.issue_to_id}"
			else						
				errorMsg = "Error linking Task #{link.issue_from_id} to #{link.issue_to_id}! More Info:  #{relation.errors.messages}"
				logger.info errorMsg
				@errorMessages += errorMsg + "<br>"
			end           		    
	  end
  end
  
  flash[:error] = @errorMessages unless @errorMessages.blank?
  return {:new_parent_created => new_parent_created, :issues_imported => issues_imported}
  end
    
  
  def find_project
    @project = Project.find(params[:project_id])
  end
end