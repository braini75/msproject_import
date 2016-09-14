# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

RedmineApp::Application.routes.draw do    
    match 'msproject_import/(:action(/:id))',via: [:get, :post], :controller => 'msproj_imp'
end