module MsprojectImport
	USE_WORK = true
	IMPORT_SUMMARY = false
	
	class << self
		
		def use_work
			if Setting.plugin_msproject_import['use_work'].nil?
				USE_WORK
			else
				if Setting.plugin_msproject_import['use_work'] == '1'
					true
				else
					false
				end
			end
		end
		
		def import_summary
			if Setting.plugin_msproject_import['import_summary'].nil?
				IMPORT_SUMMARY
			else
				if Setting.plugin_msproject_import['import_summary'] == '1'
					true
				else
					false
				end
			end
		end
	end
end