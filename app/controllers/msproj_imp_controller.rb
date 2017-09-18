class MsprojImpController < ApplicationController
  unloadable
  require 'rexml/document'
  require 'date'
  
  before_action :find_project, :only => [:analyze, :upload, :import_results, :init_run, :run]
  before_action :init_cache, :only => [:analyze, :upload, :import_results]
  before_filter :read_cache, :only => [:import_results, :status, :init_run, :run]
  after_filter  :write_cache, :only => [:analyze]
  after_filter :clear_flash
  
  include MsprojImpHelper  
  
  def upload
	 flash.clear
	 @parent_issues = get_issue_project_parent
  end 
  
  def init_run
  	@parent_issue = @@cache.read(:parent_issue)	
  	@@cache.write(:add_IssueSuffix,params[:add_IssueSuffix]) if params[:add_IssueSuffix]
  	@@cache.write(:add_wbs2name,params[:add_wbs2name]) if params[:add_wbs2name]    
  	
  	if params[:erase_issues]
  		if delete_issues < 0
  		  @parent_issues = get_issue_project_parent
  			render :action => 'upload'
  			return
  		end
  	end
  	
  	if @@cache.read(:params).nil?
  		@@cache.write(:params, params)
  	end
  	
  	redirect_to msproj_imp_run_path(:project_id => @project)
  end
  
  def run
  	Rails.logger.info("run.................")
  	if request.post?
  		process_tasks({:max_items => max_items_per_request, :max_time => 10.seconds}, session[:current])
  		respond_to do |format|
  			format.html {
  				if session[:finished]
  					import_predecesor
  					@project.issues.reload
  					redirect_to msproj_imp_import_results_path(:project_id => @project)
  				else
  					Rails.logger.info("redirect run.................")
  					redirect_to msproj_imp_run_path(:project_id => @project)
  				end
  			}
  			Rails.logger.info("js run.................")
  			format.js
  		end
  	end
  end
  
  def import_results
  	if @@cache.read(:issues_imported_list).nil?
  		@issues_imported = []
  	else
  		list = @@cache.read(:issues_imported_list)
  		@issues_imported = Issue.where(:id => list).order(:id).to_a || []
  		list = nil
  	end
  	if !@@cache.read(:errorMessages).nil?
  		flash[:warning] = @@cache.read(:errorMessages)
  	end
  	@@cache.clear
  	session[:finished] = nil
  	session[:current] = nil
  end

  def analyze
    
	if params[:upload]
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
		
		# Set Parent issue according selection		
		parent_issue = Issue.find(params[:parent_issue]) unless params[:parent_issue].empty?
		logger.info "Parent: #{parent_issue}"
		@@cache.write(:parent_issue, parent_issue)
		
		if params[:erase_issues]
		  if params[:parent_issue].empty?
		    # Delete whole project
		    @issues2delete_count = @project.issues.count
		  else
		    @issues2delete_count = Issue.select(:id).order(id: :desc).where("root_id = ? AND id != ?", parent_issue.id, parent_issue.id).count  		    
		  end
      
    end

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
				@resources.push(xml_resources(child))
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
					@tasks.push(xml_tasks(child))
					if child.elements['OutlineLevel'].text == '0'
						project_parent_issue = true
					end
				else
					if child.elements['OutlineLevel'].text == '0'
						if child.elements['IsNull'].text == "0"
							task = xml_tasks(child)
							if task
								task.name = session[:title]
								@tasks.push(task)
								project_parent_issue = true
							else
								if error != ''
									error = error + "<br>" + "No project parent task was found."
								else
									error = "No project parent task was found."
								end
								@task_skipped += child.elements['ID'].text + " "
							end
						else
							if error != ''
								error = error + "<br>" + "No project parent task was found."
							else
								error = "No project parent task was found."
							end
							@task_skipped += child.elements['ID'].text + " "
						end
					else
						@task_skipped += child.elements['ID'].text + " "
					end
				end
			end
			logger.info "Task passed!"
		end
		session[:current] = nil
		if !project_parent_issue
			flash[:error] = error
			flash[:warning] = warning unless warning.blank?
			@parent_issues = get_issue_project_parent
			render :action => 'upload'
		else
			extra_info = ""
			extra_info = "<br>Following empty tasks skipped: " + @task_skipped + "!" unless @task_skipped.blank?
			flash[:notice] = "Project parsed" + extra_info 
			flash[:warning] = warning unless warning.blank?
		end
	else
		flash[:error] = l(:file_required)
		@parent_issues = get_issue_project_parent
		render :action => 'upload'
	end
  end
  
  private
  
  def process_tasks(options={}, resume_after)
  	max_items = options[:max_items]
    max_time = options[:max_time]
    imported = 0
  	position = 1
  	if resume_after.nil?
  		resume_after = 0
  	end
    interrupted = false
    started_on = Time.now

    @tasks.each do |task|
      if (max_items && imported >= max_items) || (max_time && Time.now >= started_on + max_time)
        interrupted = true
        break
      end
      if position > resume_after
        #Do import
        imported += 1
		    import(task)
      end
	    position += 1
    end

    if imported == 0 || !interrupted
      session[:finished] = true
	  else
		  session[:finished] = false
    end
	  session[:current] = position - 1
  end
  
  def delete_issues()    
  	begin
  		Rails.logger.info("----------------------DELETING ISSUES-------------------")
  		if @parent_issue
  		  logger.info("Parent issue #{@parent_issue.id} found. Delete all subissues.")
  		  issues = Issue.select(:id).order(id: :desc).where("root_id = ? AND id != ?", @parent_issue.id, @parent_issue.id).to_a || []
  		  if issues.size > 0
          Issue.destroy(issues)        
          Rails.logger.info("----------------------ALL ISSUES BELOW #{@parent_issue.id} WERE DELETED------------------")
        end
  		else
  		  logger.info("No Parent issue selecte. Clean Project")
  		  @project.issues.clear # just delete the complete project
  		  Rails.logger.info("----------------------ALL ISSUES IN PROJECT WERE DELETED------------------")
  		end
  		
  		return 0
  	rescue => exception
  	  err_msg = "Error: " + "#{exception.class}: #{exception.exception}"
  		Rails.logger.info("---------------------EXCEPCION------------------------------")
  		Rails.logger.info(err_msg)
  		flash[:error] = err_msg
  		return -1
  	end
  end
  
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
  
  def update_cache(data)
	if @@cache.read(:parent_issue).nil?
		@@cache.write(:parent_issue, data[:issue_created])
	end
	
	@@cache.write(:last_issue_id, data[:last_issue_id])
	@@cache.write(:last_outline_level, data[:last_outline_level])
	@@cache.write(:parent_stack, data[:parent_stack])
	@@cache.write(:mapUID2IssueID, data[:mapUID2IssueID])
	
	if @@cache.read(:issues_imported_list).nil?
		list = []
	else
		list = @@cache.read(:issues_imported_list)
	end
	list.push(data[:issue_created].id)
	@@cache.write(:issues_imported_list, list)
  end
  
	def import(task)
		logger.info "Start Import Task " + task.task_uid.to_s 
		
		if @@cache.read(:parent_issue).nil?
			root_id = 0
		else
			Rails.logger.info("Setting root id to: " + @@cache.read(:parent_issue).id.to_s)
			root_id = @@cache.read(:parent_issue).id
		end
		
		if @@cache.read(:last_issue_id).nil?
			last_issue_id = 0
		else
			last_issue_id = @@cache.read(:last_issue_id)
		end
		
		if @@cache.read(:last_outline_level).nil?
			last_outline_level = 0
		else
			last_outline_level = @@cache.read(:last_outline_level)
		end
		
		if @@cache.read(:parent_stack).nil?
			parent_stack = Array.new
		else
			parent_stack = @@cache.read(:parent_stack)
		end
		
		if @@cache.read(:mapUID2IssueID).nil?
			mapUID2IssueID = [] # maps UIDs to redmine issue_id
		else
			mapUID2IssueID = @@cache.read(:mapUID2IssueID)
		end

		import_task_result = import_task(task, root_id, last_issue_id, parent_stack, last_outline_level, mapUID2IssueID)
		
		if import_task_result[:issue_created]
			update_cache(import_task_result)
		else
			if @@cache.read(:errorMessages).nil?
				@@cache.write(:errorMessages, import_task_result[:errorMessages])
			else
				errorMessages = @@cache.read(:errorMessages) + "<br>" + import_task_result[:errorMessages]
				@@cache.write(:errorMessages, errorMessages)
			end
		end
	end
  
	def import_task(task, root_id, last_issue_id, parent_stack, last_outline_level, mapUID2IssueID)
		logger.info("Start - last_outline_level: " + last_outline_level.to_s)
		logger.info("Start - parent_stack " + parent_stack.to_s)
		issue = Issue.new(:author => User.current, :project  => @project)
		issue.tracker_id = Setting.plugin_msproject_import['tracker_default']  # 1-Bug, 2-Feature...
		if task.task_uid > 0
		  subject = ""
      subject = @@cache.read(:add_IssueSuffix) + " " unless @@cache.read(:add_IssueSuffix).nil?
      subject = subject + task.wbs + " " unless @@cache.read(:add_wbs2name).nil?
			issue.subject = subject + task.name
			assign=@assignments.select{|as| as.task_uid == task.task_uid}.first
			unless assign.nil? 
				logger.info("Assign: #{assign}")
				mapped_user=@usermapping.select { |id, name, user_obj, status| id == assign.resource_uid and status < 3}.first
				logger.info("Mapped User: #{mapped_user}")
				if mapped_user.nil?
					#Find manually asignment
					params_aux = @@cache.read(:params)
					if params_aux['map_user_to_' + assign.resource_uid.to_s] && !params_aux['map_user_to_' + assign.resource_uid.to_s].blank?
						logger.info("setting asignment: " + params_aux['map_user_to_' + assign.resource_uid.to_s])
						issue.assigned_to_id = params_aux['map_user_to_' + assign.resource_uid.to_s].to_i
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
		issue.done_ratio = task.done_ratio    
		issue.start_date = task.start_date
		issue.due_date = task.finish_date

		# subtask?            
		if task.outline_level > 0
			issue.root_id = root_id
			if task.outline_level > last_outline_level && last_issue_id > 0
				parent_id = last_issue_id        
				parent_stack.push(parent_id)
				logger.info("Adding level: " + parent_stack.last.to_s)
			end

			if task.outline_level < last_outline_level # step back in hierarchy
				steps = last_outline_level - task.outline_level
				parent_stack.pop(steps)  
				parent_id = parent_stack.last
				logger.info("Getting level: " + parent_id.to_s)
			end
			
			if task.outline_level == last_outline_level
				logger.info("Same level: " + last_outline_level.to_s + " parent_stack.last: " + parent_stack.last.to_s)
				parent_id = parent_stack.last
			end
			
			issue.parent_id = parent_id
		else
			if !root_id.nil? && root_id > 0
				issue.parent_id = root_id
				issue.root_id = root_id
			end
		end

		#This value must set after process taks outline level
		last_outline_level = task.outline_level
		
		# required custom fields:
		update_custom_fields(issue, @required_custom_fields)

		if task.done_ratio.to_i == 100
			issue.status_id = 5   # 5-closed
		else
			if task.done_ratio.to_i == 0
				issue.status_id = 1   # 1-New
			else
				issue.status_id = 2   # 2-In Progress
			end
		end
		
		if MsprojectImport.import_summary
			if MsprojectImport.use_work
				issue.estimated_hours = task.work
			else
				issue.estimated_hours = task.duration
			end
		else
			if task.summary == '0'
				if MsprojectImport.use_work
					issue.estimated_hours = task.work
				else
					issue.estimated_hours = task.duration
				end
			end
		end

		if issue.save   
			mapUID2IssueID[task.task_uid]= issue.id
			last_issue_id = issue.id
			logger.info "New issue #{issue.subject} in Project: #{@project} created!"     
			return {:issue_created => issue, :errorMessages => '', :mapUID2IssueID => mapUID2IssueID, :last_issue_id => last_issue_id, :last_outline_level => last_outline_level, :parent_stack => parent_stack}
		else
			errorMessages = "Issue #{task.name} Task #{task.task_id} gives Error: #{issue.errors.full_messages}"
			logger.info errorMessages
			return {:issue_created => nil, :errorMessages => errorMessages, :mapUID2IssueID => nil, :last_issue_id => nil, :last_outline_level => nil, :parent_stack => nil}
		end
	end
  
	def import_predecesor
		#Verify
		@predecessor_link.each do |link|	    
			relation = IssueRelation.new
			#logger.info "Link Info #{link} from_id: #{link.issue_from_id}"
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
				if @@cache.read(:errorMessages).nil?
					@@cache.write(:errorMessages, errorMsg)
				else
					errorMessages = @@cache.read(:errorMessages) + "<br>" + errorMsg
					@@cache.write(:errorMessages, errorMessages)
				end
			end           		    
		end
	end
	
	# Get projects parent issue
	def get_issue_project_parent	   
	    project = Project.find(params[:project_id]) 
      issues = Issue.visible.where("project_id = ? and issues.parent_id is null", project).to_a || []
      logger.info "Get projects parent issue: #{issues}"
      if issues && issues.size >= 1
        return issues
      else
        return []
      end
	end
	
	def find_project
		@project = Project.find(params[:project_id])
	end
  
	def max_items_per_request
		5
	end
end