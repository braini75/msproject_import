class MsprojResource
  attr_accessor :uid
  attr_accessor :name
  attr_reader   :info
  attr_reader   :status # 1=User found, 2=User not Member of Project, 3=User not found
  
  def map_user(members)
    status=-1
    #name_arr = name.split(/\W+/) # Split on one or more non-word characters. Problem no german Umlaut
    name_arr = name.split(/[\,]?\s+/) # Split on comma or whitespace
    users_found = User.where("firstname LIKE ? AND lastname LIKE ?", "%#{name_arr[0]}%", "%#{name_arr[1]}%")
    users_found += User.where("firstname LIKE ? AND lastname LIKE ?", "%#{name_arr[1]}%", "%#{name_arr[0]}%")
	users_found += User.where("login = lower(?)", name_arr[0].downcase)
    
    unless users_found.empty?      
      # test if user is member of project      
      user = users_found.select{ |u| members.include?(u.id)}.first
      
      unless user.nil?        
        @status=1
      else
        @status=2
        user=users_found.first
      end
    else
      @status=3      
    end
    
    if user.nil?
      return "not found"
    else
      return user  
    end
    
  end

end