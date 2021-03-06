require 'rails_helper'

RSpec.describe SourcesController, type: :controller do
  let(:organization) { create(:organization) }

  def default_url_options
    super.merge!({ :organization_id => organization.id })
  end

  describe "POST :import" do
    let(:source) { build(:source, :organization => organization) }
    let(:source_attrs) { source.attributes.reject {|k,v| v.nil? } }

    context "with a non-unique URL" do
      before(:each) { create(:source, :url => source.url) }

      it "should not create a new source object" do
        expect {
          post :import, :params => { :source => source_attrs }
        }.to_not change { Source.count }
      end

      it "should persist changs to the source object" do
        post :import, :params => { :source => { :url => source.url, :title => "undisclosed" } }
        expect(assigns(:source).reload.title).to eq "undisclosed"
      end

      it "should try to import assocated events" do
        expect_any_instance_of(SourceImporter).to receive(:import!)
        post :import, :params => { :source => source_attrs }
      end
    end

    context "with a unique URL" do
      it "should save a new source object" do
        expect {
          post :import, :params => { :source => source_attrs }
        }.to change { Source.count }.by(1)
      end

      it "should try to import assocated events" do
        expect_any_instance_of(SourceImporter).to receive(:import!)
        post :import, :params => { :source => source_attrs }
      end
    end

    describe "is given problematic sources" do
      before do
        expect(Source).to receive(:find_or_create_from).and_return(source)
      end

      def assert_import_raises(exception)
        expect_any_instance_of(SourceImporter).to receive(:import!).and_raise(exception)
        post :import, :params => { :source => {:url => "http://invalid.host"} }
      end

      it "should fail when host responds with an error" do
        assert_import_raises(OpenURI::HTTPError.new("omfg", "bbq"))
        expect(flash[:failure]).to match /Couldn't download events/
      end

      it "should fail when host is not responding" do
        assert_import_raises(Errno::EHOSTUNREACH.new("omfg"))
        expect(flash[:failure]).to match /Couldn't connect to remote site/
      end

      it "should fail when host is not found" do
        assert_import_raises(SocketError.new("omfg"))
        expect(flash[:failure]).to match /Couldn't find IP address for remote site/
      end

      it "should fail when host requires authentication" do
        assert_import_raises(SourceParser::HttpAuthenticationRequiredError.new("omfg"))
        expect(flash[:failure]).to match /requires authentication/
      end
    end

    it "should limit the number of created events to list in the flash" do
      max_display = SourcesController::MAXIMUM_EVENTS_TO_DISPLAY_IN_FLASH
      events = 1.upto(max_display + 5).map { build_stubbed(:event) }
      expect_any_instance_of(SourceImporter).to receive(:import!) do
        allow_any_instance_of(Source).to receive(:events).and_return(events)
      end

      post :import, :params => { :source => { :url => source.url, :title => 'My Title' } }
      expect(flash[:success]).to match /And 5 other events/si
    end
  end

  describe "GET :show" do
    context "source doesn't exist" do
      it "should redirect to the new source page" do
        get :show, :params => { :id => 'MI7' }
        expect(response).to redirect_to(new_organization_source_path)
      end

      it "should provide a failure message" do
        get :show, :params => { :id => 'MI7' }
        expect(flash[:failure]).to be_present
      end
    end

    context "source exists" do
      let(:source) { create(:source, :organization => organization) }

      it "should be successful" do
        get :show, :params => { :id => source.id }
        expect(response).to be_success
      end

      it "should assign the source to @source" do
        get :show, :params => { :id => source.id }
        expect(assigns(:source)).to eq source
      end

      context ":format => :html" do
        it "should render the :show template" do
          get :show, :params => { :id => source.id, :format => :html }
          expect(response).to render_template(:show)
        end
      end

      context ":format => :xml" do
        it "should render the source as xml" do
          get :show, :params => { :id => source.id, :format => :xml }
          expect(response.content_type).to eq 'application/xml'
        end
      end
    end
  end

  describe "GET :new" do
    it "should be successful" do
      get :new
      expect(response).to be_success
    end

    it "should assign the newly initialized source to @source" do
      get :new
      expect(assigns(:source)).to be_present
    end

    it "@source should be a new record" do
      get :new
      expect(assigns(:source).new_record?).to be true
    end

    context ":format => :html" do
      it "should render the :new template" do
        get :new, :params => { :format => :html }
        expect(response).to render_template(:new)
      end
    end
  end

  describe "GET :edit", :requires_user do
    def test_authenticated_request
      source = create(:source, :organization => organization)
      get :edit, :params => { :id => source.id }
    end

    context "source doesn't exist" do
      it "should raise an error" do
        expect { get :edit, :params => { :id => 'MI7' } }
          .to raise_error ActiveRecord::RecordNotFound
      end
    end

    context "source exists" do
      let(:source) { create(:source, :organization => organization) }

      it "should be successful" do
        get :edit, :params => { :id => source.id }
        expect(response).to be_success
      end

      it "should assign the source to @source" do
        get :edit, :params => { :id => source.id }
        expect(assigns(:source)).to eq source
      end

      context ":format => :html" do
        it "should render the :edit template" do
          get :edit, :params => { :id => source.id, :format => :html }
          expect(response).to render_template(:edit)
        end
      end
    end
  end

  describe "POST :create" do
    context "with valid source attributes" do
      # attributes_for(:source) doesn't return what I expect w/ this version of FG
      let(:source_attrs) { build(:source, :organization => organization).attributes }

      it "should save the source object" do
        expect {
          post :create, :params => { :source => source_attrs }
        }.to change { Source.count }.by(1)
      end

      it "should assign the source to @source" do
        post :create, :params => { :source => source_attrs }
        expect(assigns(:source)).to_not be_nil
      end

      it "should redirect to the source show page" do
        post :create, :params => { :source => source_attrs }

        path = organization_source_path(
          :organization_id => organization.id,
          :id => assigns(:source).id
        )

        expect(response).to redirect_to(path)
      end
    end

    context "with invalid source attributes" do
      it "should not save the source object" do
        expect { post :create, :params => { :source => {} } }
          .to_not change { Source.count }
      end

      it "should render the :new template" do
        post :create, :params => { :source => {} }
        expect(response).to render_template(:new)
      end
    end
  end

  describe "PUT :update", :requires_user do
    def test_authenticated_request
      source = create(:source, :organization => organization)
      put :update, :params => { :id => source.id, :source => source.attributes }
    end

    context "source doesn't exist" do
      it "should raise an error" do
        expect { put :update, :params => { :id => 'MI7' } }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "source exists" do
      let(:source) { create(:source, :organization => organization) }

      it "should assign the source to @source" do
        put :update, :params => { :id => source.id, :source => source.attributes }
        expect(assigns(:source)).to_not be_nil
      end

      context "source changes are valid" do
        it "should persist changs to the source object" do
          put :update, :params => { :id => source.id, :source => { :title => "undisclosed" } }
          expect(assigns(:source).reload.title).to eq "undisclosed"
        end

        it "should redirect to the source show page" do
          put :update, :params => { :id => source.id, :source => source.attributes }

          path = organization_source_path(
            :organization_id => organization.id,
            :id => assigns(:source).id
          )

          expect(response).to redirect_to(path)
        end
      end

      context "source changes are invalid" do
        it "should not persist changes to the source object" do
          put :update, :params => { :id => source.id, :source => { :url => "" } }
          expect(assigns(:source).reload.url).to eq source.url
        end

        it "should render the :edit template" do
          put :update, :params => { :id => source.id, :source => { :url => "" } }
          expect(response).to render_template(:edit)
        end

        it "should provide an error message" do
          put :update, :params => { :id => source.id, :source => { :url => "" } }
          expect(flash[:error]).to be_present
        end
      end
    end
  end

  describe "DELETE :destroy", :requires_user do
    def test_authenticated_request
      source = create(:source, :organization => organization)
      delete :destroy, :params => { :id => source.id }
    end

    context "source doesn't exist" do
      it "should raise an error" do
        expect { delete :destroy, :params => { :id => 'MI7' } }
          .to raise_error ActiveRecord::RecordNotFound
      end
    end

    context "source exists" do
      let(:source) { create(:source, :organization => organization) }

      it "should remove the object from the database" do
        source # initialize now, let(...) is lazy

        expect {
          delete :destroy, :params => { :id => source.id }
        }.to change { Source.count }.by(-1)
      end

      it "should call destroy on source object (not delete)" do
        # we want to ensure any destroy hooks are triggered (paper trail, etc)
        expect_any_instance_of(Source).to receive(:destroy)
        delete :destroy, :params => { :id => source.id }
      end

      it "should redirect to the index page" do
        delete :destroy, :params => { :id => source.id }
        expect(response).to redirect_to(organization_url(:id => organization.id))
      end
    end
  end

end
