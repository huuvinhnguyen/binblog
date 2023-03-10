class ProjectsController < ApplicationController
  def index
    @projects = Project.all
  end

  def show
    @employee = Employee.find(session[:employee_id]) # truy cập thông tin employee từ session
    @project = Project.find(params[:id])
  end

  def new
    @project = Project.new
    @employee = Employee.find(session[:employee_id]) # truy cập thông tin employee từ session
  end

  def create
    
    @project = Project.new(project_params)

    if @project.save
      redirect_to @project
    else
      render 'new'
    end
  end

  def edit
    @project = Project.find(params[:id])
  end

  def update
    @project = Project.find(params[:id])

    if @project.update(project_params)
      redirect_to @project
    else
      render 'edit'
    end
  end

  def destroy
    @project = Project.find(params[:id])
    @project.destroy

    redirect_to projects_path
  end

  private

  def project_params
    params.require(:project).permit(:name)
  end
end
