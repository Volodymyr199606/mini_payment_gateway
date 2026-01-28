import { application } from "@hotwired/stimulus-loading"

application.load(import.meta.glob("./**/*_controller.js"))
