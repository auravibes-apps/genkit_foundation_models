import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  @available(iOS 26.0, macOS 26.0, *)
  struct NativeJSONSchemaConverter {
    let schema: [String: Any]

    func makeSchema() -> DynamicGenerationSchema? {
      dynamicSchema(from: schema, name: schema["title"] as? String ?? "Input")
    }

    private func dynamicSchema(
      from schema: [String: Any],
      name: String
    ) -> DynamicGenerationSchema? {
      let description = schema["description"] as? String
      return switch schema["type"] as? String {
      case "boolean": DynamicGenerationSchema(type: Bool.self)
      case "integer": DynamicGenerationSchema(type: Int.self)
      case "number": DynamicGenerationSchema(type: Double.self)
      case "string": stringSchema(from: schema, name: name, description: description)
      case "array": arraySchema(from: schema, name: name)
      case "object", nil: objectSchema(from: schema, name: name, description: description)
      default: nil
      }
    }

    private func stringSchema(
      from schema: [String: Any],
      name: String,
      description: String?
    ) -> DynamicGenerationSchema {
      if let values = schema["enum"] as? [String], !values.isEmpty {
        return DynamicGenerationSchema(name: name, description: description, anyOf: values)
      }
      return DynamicGenerationSchema(type: String.self)
    }

    private func arraySchema(
      from schema: [String: Any],
      name: String
    ) -> DynamicGenerationSchema? {
      let itemSchema = (schema["items"] as? [String: Any]).flatMap {
        dynamicSchema(from: $0, name: "\(name)Item")
      } ?? DynamicGenerationSchema(type: String.self)
      return DynamicGenerationSchema(arrayOf: itemSchema)
    }

    private func objectSchema(
      from schema: [String: Any],
      name: String,
      description: String?
    ) -> DynamicGenerationSchema {
      let required = Set(schema["required"] as? [String] ?? [])
      let properties = (schema["properties"] as? [String: Any] ?? [:])
        .map { key, value -> DynamicGenerationSchema.Property in
          let propertySchema = value as? [String: Any] ?? [:]
          let dynamicPropertySchema = dynamicSchema(
            from: propertySchema,
            name: key
          ) ?? DynamicGenerationSchema(type: String.self)
          return DynamicGenerationSchema.Property(
            name: key,
            description: propertySchema["description"] as? String,
            schema: dynamicPropertySchema,
            isOptional: !required.contains(key)
          )
        }
      return DynamicGenerationSchema(
        name: name,
        description: description,
        properties: properties
      )
    }
  }
#endif
