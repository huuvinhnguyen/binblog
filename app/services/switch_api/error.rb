module SwitchApi
  class Error < StandardError
    attr_reader :code, :status, :outcome

    def initialize(code, status: :unprocessable_entity, outcome: nil)
      @code, @status, @outcome = code, status, outcome
      super(code)
    end
  end
end
