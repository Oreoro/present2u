module Api
  # Reports the compiler toolchain: markdown/highlight engines, math, diagram
  # engines and the external binaries with their versions and availability.
  class ToolchainController < BaseController
    # GET /api/toolchain
    def show
      render json: { toolchain: P2u::Toolchain.report }
    end
  end
end
