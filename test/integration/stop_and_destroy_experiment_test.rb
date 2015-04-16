require 'test_helper'
require 'json'
require 'db_helper'

class StopAndDestroyExperimentTest < ActionDispatch::IntegrationTest
  include DBHelper

  OWNER_NAME = 'owner'
  OWNER_PASSWORD = 'owner_password'
  COWORKER_NAME = 'coworker'
  COWORKER_PASSWORD = 'coworker_password'

  STOP_REASON = 'You cannot stop this experiment because you are not its owner'
  DESTROY_REASON = 'You cannot destroy this experiment because you are not its owner'

  @@owner = ScalarmUser.new({login: OWNER_NAME})
  @@coworker = ScalarmUser.new({login: COWORKER_NAME})
  @@experiment

  def setup
    super
    # create two users, log in one and set sample shared experiment
    @@owner.password = OWNER_PASSWORD
    @@owner.save

    @@coworker.password = COWORKER_PASSWORD
    @@coworker.save
    post login_path, username: COWORKER_NAME, password: COWORKER_PASSWORD

    @@experiment = Experiment.new({user_id: @@owner.id})
    @@experiment.add_to_shared(@@coworker.id)
    @@experiment.save

    # mock information service
    information_service = mock
    information_service.stubs(:get_list_of).returns([])
    information_service.stubs(:sample_public_url).returns(nil)
    InformationService.stubs(:new).returns(information_service)
  end

  test 'unsuccessful stopping experiment by non-owner coworker with json response' do

    post "#{stop_experiment_path(@@experiment.id)}.json"

    response_hash = JSON.parse(response.body)
    assert_nothing_raised do
      response_hash.assert_valid_keys('status', 'reason')
    end

    assert_equal response.status, 412
    assert_equal response_hash['status'], 'error'
    assert_equal response_hash['reason'], STOP_REASON

  end

  test 'unsuccessful stopping experiment by non-owner coworker with html response' do

    post stop_experiment_path(@@experiment.id)

    assert_redirected_to experiments_path
    assert_equal flash['error'], STOP_REASON

  end

  test 'unsuccessful destroying experiment by non-owner coworker with json response' do

    @@experiment.is_running = false
    @@experiment.save

    delete "#{experiment_path(@@experiment.id)}.json"

    response_hash = JSON.parse(response.body)
    assert_nothing_raised do
      response_hash.assert_valid_keys('status', 'reason')
    end

    assert_equal response.status, 412
    assert_equal response_hash['status'], 'error'
    assert_equal response_hash['reason'], DESTROY_REASON

  end

  test 'unsuccessful destroying experiment by non-owner coworker with html response' do

    @@experiment.is_running = false
    @@experiment.save

    delete experiment_path(@@experiment.id)

    assert_redirected_to experiments_path
    assert_equal flash['error'], DESTROY_REASON

  end
end
