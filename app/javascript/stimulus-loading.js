// Exposes the Stimulus application instance for controller loading.
// Controllers load this and call application.load(import.meta.glob(...)).
import { Application } from "@hotwired/stimulus"

const application = Application.start()
export { application }
