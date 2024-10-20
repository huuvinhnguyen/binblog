class RewardsPenaltiesController < ApplicationController
    before_action :set_employee
    before_action :set_reward_penalty, only: [:edit, :update, :destroy]
  
    # New action for creating a new RewardPenalty
    def new
      @reward_penalty = @employee.rewards_penalties.build
    end
  
    # Create action to save a new RewardPenalty
    def create
      @reward_penalty = @employee.rewards_penalties.build(reward_penalty_params)
      
      if @reward_penalty.save
        redirect_to employee_path(@employee), notice: 'Thưởng/Phạt đã được thêm thành công.'
      else
        render :new, status: :unprocessable_entity
      end
    end
  
    # Edit action to update an existing RewardPenalty
    def edit
    end
  
    # Update action to save changes to an existing RewardPenalty
    def update
      if @reward_penalty.update(reward_penalty_params)
        redirect_to employee_path(@employee), notice: 'Thưởng/Phạt đã được cập nhật thành công.'
      else
        render :edit, status: :unprocessable_entity
      end
    end
  
    # Destroy action to delete a RewardPenalty
    def destroy
      @reward_penalty.destroy
      redirect_to employee_path(@employee), notice: 'Thưởng/Phạt đã được xóa.'
    end
  
    private
  
    # Set the employee for nested resource routes
    def set_employee
      @employee = Employee.find(params[:employee_id])
    end
  
    # Set the RewardPenalty for editing/updating
    def set_reward_penalty
      @reward_penalty = @employee.rewards_penalties.find(params[:id])
    end
  
    # Permit the necessary parameters
    def reward_penalty_params
      params.require(:rewards_penalty).permit(:description, :penalty, :amount, :date)
    end
end
  