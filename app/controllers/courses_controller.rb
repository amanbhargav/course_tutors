class CoursesController < ApplicationController
  def index
    courses = Course.includes(:tutors).order(:created_at)
    render json: courses.map { |course| course_json(course) }
  end

  def create
    course = Course.new(course_params)

    if course.save
      render json: course_json(course), status: :created
    else
      render json: { errors: course.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def course_params
    params.require(:course).permit(:name, :description, tutors_attributes: [ :name, :email ])
  end

  def course_json(course)
    {
      id: course.id,
      name: course.name,
      description: course.description,
      tutors: course.tutors.map do |tutor|
        {
          id: tutor.id,
          name: tutor.name,
          email: tutor.email
        }
      end
    }
  end
end
