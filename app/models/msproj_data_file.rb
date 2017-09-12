class MsprojDataFile
	require 'fileutils'
    attr_accessor :upload
	
  def self.save(upload)
  
    file_name = upload['datafile'].original_filename if  (upload['datafile'] !='')
	@content = upload['datafile'].read
	
	file_type = file_name.split('.').last
	
    directory = 'public/plugin_assets/msproject_import/uploads'
	
	FileUtils.mkdir_p directory
	
    # create the file path
    path = File.join(directory,file_name)
    # write the file
    File.open(path, "wb") { |f| f.write(@content)}
	return path
  end
  
  def self.content()
	return @content
  end  	
	
end