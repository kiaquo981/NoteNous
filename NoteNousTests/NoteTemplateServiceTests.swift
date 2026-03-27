import XCTest
@testable import NoteNous

final class NoteTemplateServiceTests: XCTestCase {

    private var service: NoteTemplateService!

    override func setUp() {
        super.setUp()
        service = NoteTemplateService()
        // Clean up any leftover custom templates
        for t in service.customTemplates {
            service.deleteCustomTemplate(id: t.id)
        }
    }

    override func tearDown() {
        // Clean up
        for t in service.customTemplates {
            service.deleteCustomTemplate(id: t.id)
        }
        service = nil
        super.tearDown()
    }

    // MARK: - Built-in Templates

    func testBuiltInTemplates() {
        XCTAssertEqual(NoteTemplateService.builtInTemplates.count, 9, "Should have 9 built-in templates")
    }

    // MARK: - Render Template

    func testRenderTemplate() {
        let template = NoteTemplateService.builtInTemplates.first! // Fleeting template
        let values = ["title": "My Idea", "content": "This is my idea"]
        let (title, content, _) = service.render(template: template, values: values)

        XCTAssertEqual(title, "My Idea", "Title should be substituted from values")
        XCTAssertTrue(content.contains("My Idea"), "Content should contain the substituted title")
        XCTAssertTrue(content.contains("This is my idea"), "Content should contain the substituted content")
        XCTAssertFalse(content.contains("{{title}}"), "No unreplaced placeholders should remain for provided values")
        XCTAssertFalse(content.contains("{{content}}"), "No unreplaced placeholders should remain for provided values")
    }

    // MARK: - Custom Template CRUD

    func testCustomTemplateCreate() {
        let initialCount = service.allTemplates.count

        service.addCustomTemplate(
            name: "Test Template",
            noteType: .fleeting,
            contentTemplate: "# {{title}}\n\n{{content}}",
            defaultPARA: .inbox
        )

        XCTAssertEqual(service.allTemplates.count, initialCount + 1)
        XCTAssertEqual(service.customTemplates.count, 1)
        XCTAssertEqual(service.customTemplates.first?.name, "Test Template")
    }

    func testCustomTemplateDelete() {
        let template = service.addCustomTemplate(
            name: "To Delete",
            noteType: .fleeting
        )

        XCTAssertEqual(service.customTemplates.count, 1)

        service.deleteCustomTemplate(id: template.id)
        XCTAssertEqual(service.customTemplates.count, 0)
    }

    // MARK: - Persistence

    func testPersistence() {
        let template = service.addCustomTemplate(
            name: "Persistent Template",
            noteType: .permanent,
            contentTemplate: "# Test"
        )
        let savedId = template.id

        // Create new instance which loads from disk
        let service2 = NoteTemplateService()
        let found = service2.template(for: savedId)
        XCTAssertNotNil(found, "Custom template should survive reload")
        XCTAssertEqual(found?.name, "Persistent Template")

        // Cleanup
        service2.deleteCustomTemplate(id: savedId)
    }
}
