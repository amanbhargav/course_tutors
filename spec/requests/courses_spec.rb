require "rails_helper"

RSpec.describe "Courses API", type: :request do
  describe "GET /courses" do
    it "returns all courses with their tutors" do
      course = create(:course, :with_tutors, name: "Advanced Ruby", tutors_count: 2)
      create(:course, name: "Empty Course")

      get "/courses"

      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body.length).to eq(2)

      first = body.find { |c| c["name"] == "Advanced Ruby" }
      expect(first["tutors"].length).to eq(2)
      expect(first["tutors"].first.keys).to match_array(%w[id name email])
      expect(first.keys).to match_array(%w[id name description tutors])

      empty = body.find { |c| c["name"] == "Empty Course" }
      expect(empty["tutors"]).to eq([])
    end

    it "returns an empty array when there are no courses" do
      get "/courses"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it "does not run an N+1 query when listing courses with tutors" do
      create(:course, :with_tutors, tutors_count: 3)
      create_list(:course, 5)

      queries = []

      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        if sql.start_with?("SELECT") && (sql.include?("FROM \"courses\"") || sql.include?("FROM \"tutors\""))
          queries << sql
        end
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/courses"
      end

      expect(response).to have_http_status(:ok)
      expect(queries).to have_attributes(length: 2)
    end
  end

  describe "POST /courses" do
    def post_courses(params)
      post "/courses", params: params, as: :json
    end

    it "creates a course with its tutors and returns 201" do
      params = {
        course: {
          name: "RSpec Mastery",
          description: "Write great tests",
          tutors_attributes: [
            { name: "Alice", email: "alice@example.com" },
            { name: "Bob", email: "bob@example.com" }
          ]
        }
      }

      expect { post_courses(params) }
        .to change { Course.count }.by(1)
        .and change { Tutor.count }.by(2)

      expect(response).to have_http_status(:created)

      body = response.parsed_body
      expect(body["name"]).to eq("RSpec Mastery")
      expect(body["tutors"].map { |t| t["name"] }).to contain_exactly("Alice", "Bob")
    end

    it "creates a course without tutors" do
      post_courses(course: { name: "Solo Course" })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["tutors"]).to eq([])
    end

    it "creates a course when tutors_attributes is an explicit empty array" do
      post_courses(course: { name: "Empty Cohort", tutors_attributes: [] })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["tutors"]).to eq([])
    end

    it "returns 422 when a tutor name is blank" do
      params = {
        course: {
          name: "Whitespace",
          tutors_attributes: [ { name: "   ", email: "eve@example.com" } ]
        }
      }

      post_courses(params)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Tutors name can't be blank")
    end

    it "returns 422 with errors when a tutor is invalid" do
      params = {
        course: {
          name: "Broken",
          tutors_attributes: [ { name: "Eve", email: "not-an-email" } ]
        }
      }

      expect { post_courses(params) }.not_to change(Course, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Tutors email is invalid")
    end

    it "returns 422 when the course name is missing" do
      params = { course: { name: "", tutors_attributes: [] } }

      post_courses(params)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include("Name can't be blank")
    end

    it "returns 400 when the course key is missing" do
      post "/courses", params: { name: "No wrapper" }

      expect(response).to have_http_status(:bad_request)
    end

    it "ignores unpermitted parameters" do
      params = {
        course: {
          name: "Secure Course",
          course_id: 999,
          tutors_attributes: [ { name: "Mallory", email: "mallory@example.com", course_id: 999 } ]
        }
      }

      post_courses(params)

      expect(response).to have_http_status(:created)

      created = Course.find_by(name: "Secure Course")
      expect(created.tutors.first.course_id).to eq(created.id)
    end
  end
end
