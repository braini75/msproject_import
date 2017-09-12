# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

RedmineApp::Application.routes.draw do
    match 'msproject_import/upload/(:id)', :to => 'msproj_imp#upload', via: [:get, :post], :as => 'msproj_imp_upload'
	match 'msproject_import/analyze/(:id)', :to => 'msproj_imp#analyze', via: [:get, :post], :as => 'msproj_imp_analyze'
	match 'msproject_import/run/(:id)', :to => 'msproj_imp#run', via: [:get, :post], :as => 'msproj_imp_run'
	match 'msproject_import/init_run/(:id)', :to => 'msproj_imp#init_run', via: [:get, :post], :as => 'msproj_imp_init_run'
	match 'msproject_import/import_results/(:id)', :to => 'msproj_imp#import_results', via: [:get, :post], :as => 'msproj_imp_import_results'
end