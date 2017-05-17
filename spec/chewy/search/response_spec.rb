require 'spec_helper'

describe Chewy::Search::Response, :orm do
  before { Chewy.massacre }

  before do
    stub_model(:city)
    stub_model(:country)

    stub_index(:places) do
      define_type City do
        field :name
        field :rating, type: 'integer'
      end

      define_type Country do
        field :name
        field :rating, type: 'integer'
      end
    end
  end

  before { PlacesIndex.import!(cities: cities, countries: countries) }

  let(:cities) { Array.new(2) { |i| City.create!(rating: i, name: "city #{i}") } }
  let(:countries) { Array.new(2) { |i| Country.create!(rating: i + 2, name: "country #{i}") } }

  let(:request) { Chewy::Search::Request.new(PlacesIndex).order(:rating) }
  let(:raw_response) { request.send(:perform) }
  let(:load_options) { {} }
  let(:loaded_objects) { false }
  subject do
    described_class.new(
      raw_response,
      indexes: [PlacesIndex],
      load_options: load_options,
      loaded_objects: loaded_objects
    )
  end

  describe '#hits' do
    specify { expect(subject.hits).to be_a(Array) }
    specify { expect(subject.hits).to have(4).items }
    specify { expect(subject.hits).to all be_a(Hash) }
    specify do
      expect(subject.hits.flat_map(&:keys).uniq)
        .to match_array(%w[_id _index _type _score _source sort])
    end

    context do
      let(:raw_response) { {} }
      specify { expect(subject.hits).to eq([]) }
    end
  end

  describe '#total' do
    specify { expect(subject.total).to eq(4) }

    context do
      let(:raw_response) { {} }
      specify { expect(subject.total).to eq(0) }
    end
  end

  describe '#max_score' do
    specify { expect(subject.max_score).to be_nil }

    context do
      let(:request) { Chewy::Search::Request.new(PlacesIndex).query(range: {rating: {lte: 42}}) }
      specify { expect(subject.max_score).to eq(1.0) }
    end
  end

  describe '#took' do
    specify { expect(subject.took).to be >= 0 }

    context do
      let(:request) do
        Chewy::Search::Request.new(PlacesIndex)
          .query(script: {script: {inline: 'sleep(100); true', lang: 'groovy'}})
      end
      specify { expect(subject.took).to be > 100 }
    end
  end

  describe '#timed_out?' do
    specify { expect(subject.timed_out?).to eq(false) }

    context do
      let(:request) do
        Chewy::Search::Request.new(PlacesIndex)
          .query(script: {script: {inline: 'sleep(100); true', lang: 'groovy'}}).timeout('10ms')
      end
      specify { expect(subject.timed_out?).to eq(true) }
    end
  end

  describe '#suggest' do
    specify { expect(subject.suggest).to eq({}) }

    context do
      let(:request) do
        Chewy::Search::Request.new(PlacesIndex).suggest(
          my_suggestion: {
            text: 'city country',
            term: {
              field: 'name'
            }
          }
        )
      end
      specify do
        expect(subject.suggest).to eq(
          'my_suggestion' => [
            {'text' => 'city', 'offset' => 0, 'length' => 4, 'options' => []},
            {'text' => 'country', 'offset' => 5, 'length' => 7, 'options' => []}
          ]
        )
      end
    end
  end

  describe '#results' do
    specify { expect(subject.results).to be_a(Array) }
    specify { expect(subject.results).to have(4).items }
    specify do
      expect(subject.results.map(&:class).uniq)
        .to contain_exactly(PlacesIndex::City, PlacesIndex::Country)
    end
    specify { expect(subject.results.map(&:_data)).to eq(subject.hits) }

    context do
      let(:raw_response) { {} }
      specify { expect(subject.results).to eq([]) }
    end

    context do
      let(:raw_response) { {'hits' => {}} }
      specify { expect(subject.results).to eq([]) }
    end

    context do
      let(:raw_response) { {'hits' => {'hits' => []}} }
      specify { expect(subject.results).to eq([]) }
    end

    context do
      let(:raw_response) do
        {'hits' => {'hits' => [
          {'_index' => 'places',
           '_type' => 'city',
           '_id' => '1',
           '_score' => 1.3,
           '_source' => {'id' => 2, 'rating' => 0}}
        ]}}
      end
      specify { expect(subject.results.first).to be_a(PlacesIndex::City) }
      specify { expect(subject.results.first.id).to eq(2) }
      specify { expect(subject.results.first.rating).to eq(0) }
      specify { expect(subject.results.first._score).to eq(1.3) }
      specify { expect(subject.results.first._explanation).to be_nil }
    end

    context do
      let(:raw_response) do
        {'hits' => {'hits' => [
          {'_index' => 'places',
           '_type' => 'country',
           '_id' => '2',
           '_score' => 1.2,
           '_explanation' => {foo: 'bar'}}
        ]}}
      end
      specify { expect(subject.results.first).to be_a(PlacesIndex::Country) }
      specify { expect(subject.results.first.id).to eq('2') }
      specify { expect(subject.results.first.rating).to be_nil }
      specify { expect(subject.results.first._score).to eq(1.2) }
      specify { expect(subject.results.first._explanation).to eq(foo: 'bar') }
    end
  end

  describe '#objects' do
    specify { expect(subject.objects).to eq([*cities, *countries]) }

    context do
      let(:load_options) { {only: 'city'} }
      specify { expect(subject.objects).to eq([*cities, nil, nil]) }
    end

    context do
      let(:load_options) { {except: 'city'} }
      specify { expect(subject.objects).to eq([nil, nil, *countries]) }
    end

    context do
      let(:load_options) { {except: %w[city country]} }
      specify { expect(subject.objects).to eq([nil, nil, nil, nil]) }
    end

    context 'scopes', :active_record do
      context do
        let(:load_options) { {scope: -> { where('rating > 2') }} }
        specify { expect(subject.objects).to eq([nil, nil, nil, countries.last]) }
      end

      context do
        let(:load_options) { {country: {scope: -> { where('rating > 2') }}} }
        specify { expect(subject.objects).to eq([*cities, nil, countries.last]) }
      end
    end
  end

  describe '#collection' do
    specify { expect(subject.collection).to eq(subject.results) }

    context do
      let(:loaded_objects) { true }
      specify { expect(subject.collection).to eq(subject.objects) }
    end
  end
end
