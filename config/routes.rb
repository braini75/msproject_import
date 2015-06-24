# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html


#get 'upload',   :to => 'msproj_imp#upload'
#post 'upload',  :to => 'msproj_imp#import'
#post 'add',     :to => 'msproj_imp#add'
#get 'add',     :to => 'msproj_imp#add'

RedmineApp::Application.routes.draw do    
    match 'msproject_import/(:action(/:id))',via: [:get, :post], :controller => 'msproj_imp'
end