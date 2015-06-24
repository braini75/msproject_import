class MsprojImpController < ApplicationController
  unloadable
  require 'rexml/document'
  require 'date'
  
  before_filter :find_project, :only => [:analyze, :upload]
  
  include MsprojImpHelper
  
  def upload
    flash.clear
  end
  
  def init_file
    
  end
   

  def analyze
    flash.clear
    if params[:do_import].nil?
          do_import='false'
        else
          do_import = params[:do_import]
    end
    
    @resources  = []
    @tasks      = []
    @assignments= []

    
    if do_import == 'true'
      @upload_path   = params[:upload_path]
      logger.info "start import from #{@upload_path}"
    else
      upload  = params[:uploaded_file]
      @upload_path   = upload.path
      logger.info "upload xml file: #{upload.class.name}: #{upload.inspect} : #{upload.original_filename} : uploaded_path: #{@upload_path}"      
    end                           

      content = File.read(@upload_path)

      #logger.info content

      doc     = REXML::Document.new(content)

      root    = doc.root
      
      @prefix="MS Project Import(#{Date.today}): "

      
      doc.elements.each('Project') do |ele|
        
        if ele.elements["Title"].nil?          
          @title = "MSProjectImport_#{User.current}:#{Date.today}"
          flash[:warning] = "No Titel in XML found. I use #{@title} instead!"
          #@title = ele.elements["Name"].text if ele.elements["Name"] 
        else
          @title = @prefix + ele.elements["Title"].text  
        end        

      ele.each_element('//Resource') do |child|
        @resources.push(xml_resources child)
#        render :text => "Resource name is: " + child.elements["Name"].text
      end

      
      resource_uids = []
      ele.each_element('//Assignment') do |child|
        assign = MsprojAssignment.new(child)
        if assign.resource_uid >= 0
          resource_uids.push(assign.resource_uid) 
          @assignments.push(assign)
        end         
      end
      
      @usermapping = []
      
      @member_uids = @project.members.map { |x| x.user_id}
      
      resource_uids.uniq.each do |resource_uid|
        resource = @resources.select { |res| res.uid == resource_uid }.first
        
        unless resource.nil?
          user = resource.map_user(@member_uids)
          logger.info("Name: #{resource.name} Res_ID #{resource_uid} USER: #{user}")
          logger.info("\n -----------INFO: #{resource.info} Status: #{resource.status}")
          unless user.nil?             
            @usermapping.push([resource_uid,resource.name, user, resource.status])
          end
        end
        #logger.debug("Mapping Resource: #{resource} UserMapping: #{@usermapping}")
        @no_mapping_found=@usermapping.select { |id, name, user_obj, status| status.to_i > 1}.count
        unless @no_mapping_found == 0
          flash[:error] = "Error: #{l(:no_failed_mapping, @no_mapping_found)}"  
        end
      end
            

      ele.each_element('//Task') do |child|
        @tasks.push(xml_tasks child)
      end
      

      end 
#      redirect_to :action => 'upload'

      flash[:notice] = "Project successful parsed" if flash.empty?

    if do_import == 'true'
           insert
    end
  end
  
  private
  def insert
    logger.info "Start insert..." 
    
    last_task_id = 0
    parent_id = 0
    root_task_id = 0
    last_outline_level = 0
        
    @tasks.each do |task|
      begin              
      issue = Issue.new(
        :author   => User.current,
        :project  => @project
        )
      issue.status_id = 1   # 1-neu
      issue.tracker_id = 2  # 1-Bug, 2-Feature...
      
      issue.subject = @title
      if task.task_id > 0
        issue.subject = task.name
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
        issue.root_id = root_task_id
        if task.outline_level > last_outline_level # new subtask
          parent_id = last_task_id           
        end
        
        issue.parent_id = parent_id 
      end
      
      last_outline_level = task.outline_level
                        
      if issue.save
        logger.info "New issue #{task.name} in Project: #{@project} created!"
        parent_task_id = 0
        last_task_id = issue.id
        root_task_id = issue.id if task.outline_level == 0     
        flash[:notice] = "Project successful inserted!"   
      else
        iss_error = issue.errors.full_messages
        logger.info "Issue #{task.name} in Project: #{@project} gives Error: #{iss_error}"
        flash[:error] = "Error: #{ex.iss_error}"   
      end
                 
      
      rescue Exception => ex
        flash[:error] = "Error: #{ex.to_s}" 
      return
      end
    end            
    
  end
  
  def find_project
    @project = Project.find(params[:project_id])
  end
end