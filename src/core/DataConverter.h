#pragma once

#include "Types.h"
#include <nlohmann/json.hpp>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <chrono>

namespace converter {

using json = nlohmann::json;

class DataConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.1f, "Reading input...");

        // Read input file
        std::ifstream inFile(job.inputPath);
        if (!inFile.is_open())
            return ConversionResult::err("Could not open input file: " + job.inputPath.string());

        std::string content((std::istreambuf_iterator<char>(inFile)),
                             std::istreambuf_iterator<char>());
        inFile.close();

        // Parse input into a common JSON pivot
        json pivot;
        try {
            const std::string& inExt = job.inputFormat.ext;
            if (inExt == "json") {
                pivot = parseJson(content);
            } else if (inExt == "csv" || inExt == "tsv") {
                char delim = (inExt == "tsv") ? '\t' : ',';
                pivot = parseCsv(content, delim);
            } else if (inExt == "xml") {
                pivot = parseXml(content);
            } else if (inExt == "yaml" || inExt == "yml") {
                pivot = parseYaml(content);
            } else if (inExt == "toml") {
                pivot = parseToml(content);
            } else {
                return ConversionResult::err("Unsupported input data format: " + inExt);
            }
        } catch (const std::exception& e) {
            return ConversionResult::err("Failed to parse input: " + std::string(e.what()));
        }

        if (job.onProgress) job.onProgress(0.5f, "Converting...");

        // Serialize pivot to output format
        std::string output;
        try {
            const std::string& outExt = job.outputFormat.ext;
            if (outExt == "json") {
                output = toJson(pivot);
            } else if (outExt == "csv" || outExt == "tsv") {
                char delim = (outExt == "tsv") ? '\t' : ',';
                output = toCsv(pivot, delim);
            } else if (outExt == "xml") {
                output = toXml(pivot);
            } else if (outExt == "yaml" || outExt == "yml") {
                output = toYaml(pivot);
            } else if (outExt == "toml") {
                output = toToml(pivot);
            } else {
                return ConversionResult::err("Unsupported output data format: " + outExt);
            }
        } catch (const std::exception& e) {
            return ConversionResult::err("Failed to serialize output: " + std::string(e.what()));
        }

        if (job.onProgress) job.onProgress(0.9f, "Writing output...");

        // Write output file
        std::ofstream outFile(job.outputPath);
        if (!outFile.is_open())
            return ConversionResult::err("Could not write output file: " + job.outputPath.string());
        outFile << output;
        outFile.close();

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result        = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes  = fs::file_size(job.inputPath);
        result.outputBytes = fs::file_size(job.outputPath);
        return result;
    }

private:
    // ── Parsers (input → JSON pivot) ─────────────────────────────────────────

    static json parseJson(const std::string& s) {
        return json::parse(s);
    }

    static json parseCsv(const std::string& s, char delim = ',') {
        json result = json::array();
        std::istringstream ss(s);
        std::string line;

        std::vector<std::string> headers;
        bool firstLine = true;

        while (std::getline(ss, line)) {
            if (line.empty()) continue;
            auto fields = splitCsvLine(line, delim);
            if (firstLine) {
                headers = fields;
                firstLine = false;
                continue;
            }
            json row = json::object();
            for (size_t i = 0; i < headers.size(); i++) {
                std::string val = (i < fields.size()) ? fields[i] : "";
                // Try to coerce to number/bool
                row[headers[i]] = coerceValue(val);
            }
            result.push_back(row);
        }
        return result;
    }

    // Minimal XML parser — handles simple flat and nested structures
    static json parseXml(const std::string& s) {
        json result;
        size_t pos = 0;

        // Skip XML declaration
        if (s.substr(0, 2) == "<?") {
            pos = s.find("?>") + 2;
        }

        skipWhitespace(s, pos);
        parseXmlElement(s, pos, result);
        return result;
    }

    // Minimal YAML parser — handles flat key: value and simple arrays
    static json parseYaml(const std::string& s) {
        std::istringstream ss(s);
        std::string line;
        std::vector<std::string> lines;

        while (std::getline(ss, line)) {
            auto commentPos = line.find('#');
            if (commentPos != std::string::npos)
                line = line.substr(0, commentPos);
            lines.push_back(line);
        }

        // Check if top level is a sequence (starts with "- ")
        bool isSequence = false;
        for (auto& l : lines) {
            std::string trimmed = trim(l);
            if (trimmed.empty()) continue;
            if (trimmed.substr(0, 2) == "- ") isSequence = true;
            break;
        }

        if (isSequence) {
            json result = json::array();
            json current = json::object();
            bool started = false;

            for (auto& l : lines) {
                std::string trimmed = trim(l);
                if (trimmed.empty()) continue;

                if (trimmed.substr(0, 2) == "- ") {
                    if (started && !current.empty())
                        result.push_back(current);
                    current = json::object();
                    started = true;
                    // Parse the key: value on the same line as "-"
                    std::string rest = trim(trimmed.substr(2));
                    auto colonPos = rest.find(':');
                    if (colonPos != std::string::npos) {
                        std::string key = trim(rest.substr(0, colonPos));
                        std::string val = trim(rest.substr(colonPos + 1));
                        current[key] = coerceValue(val);
                    }
                } else {
                    // Indented key: value inside current object
                    auto colonPos = trimmed.find(':');
                    if (colonPos != std::string::npos) {
                        std::string key = trim(trimmed.substr(0, colonPos));
                        std::string val = trim(trimmed.substr(colonPos + 1));
                        current[key] = coerceValue(val);
                    }
                }
            }
            if (started && !current.empty())
                result.push_back(current);
            return result;
        }

        // Flat object parsing (original behavior)
        json result = json::object();
        json* currentArray = nullptr;

        for (auto& l : lines) {
            std::string line2 = l;
            if (line2.find_first_not_of(" \t\r\n") == std::string::npos) continue;

            if (line2.find("  - ") == 0 || line2.find("- ") == 0) {
                size_t dashPos = line2.find("- ");
                std::string val = trim(line2.substr(dashPos + 2));
                if (currentArray) (*currentArray).push_back(coerceValue(val));
                continue;
            }

            auto colonPos = line2.find(':');
            if (colonPos != std::string::npos) {
                std::string key = trim(line2.substr(0, colonPos));
                std::string val = trim(line2.substr(colonPos + 1));
                if (val.empty()) {
                    result[key] = json::array();
                    currentArray = &result[key];
                } else {
                    currentArray = nullptr;
                    result[key] = coerceValue(val);
                }
            }
        }
        return result;
    }

    // Minimal TOML parser — flat key = value only
    static json parseToml(const std::string& s) {
        json result = json::object();
        std::istringstream ss(s);
        std::string line;
        std::string currentTable;

        while (std::getline(ss, line)) {
            auto commentPos = line.find('#');
            if (commentPos != std::string::npos)
                line = line.substr(0, commentPos);

            line = trim(line);
            if (line.empty()) continue;

            // Table header [section]
            if (line.front() == '[' && line.back() == ']') {
                currentTable = line.substr(1, line.size() - 2);
                result[currentTable] = json::object();
                continue;
            }

            auto eqPos = line.find('=');
            if (eqPos == std::string::npos) continue;

            std::string key = trim(line.substr(0, eqPos));
            std::string val = trim(line.substr(eqPos + 1));

            // Strip quotes
            if (val.size() >= 2 && val.front() == '"' && val.back() == '"')
                val = val.substr(1, val.size() - 2);

            if (currentTable.empty())
                result[key] = coerceValue(val);
            else
                result[currentTable][key] = coerceValue(val);
        }
        return result;
    }

    // ── Serializers (JSON pivot → output) ────────────────────────────────────

    static std::string toJson(const json& j) {
        return j.dump(2);
    }

    static std::string toCsv(const json& j, char delim = ',') {
        std::ostringstream ss;

        // Expect array of objects
        if (!j.is_array() || j.empty())
            throw std::runtime_error("CSV output requires an array of objects");

        // Write headers
        auto& first = j[0];
        if (!first.is_object())
            throw std::runtime_error("CSV output requires an array of objects");

        bool firstCol = true;
        for (auto& [key, _] : first.items()) {
            if (!firstCol) ss << delim;
            ss << escapeCsvField(key, delim);
            firstCol = false;
        }
        ss << "\n";

        // Write rows
        for (auto& row : j) {
            firstCol = true;
            for (auto& [key, val] : row.items()) {
                if (!firstCol) ss << delim;
                if (val.is_string())      ss << escapeCsvField(val.get<std::string>(), delim);
                else if (val.is_null())   ss << "";
                else                      ss << val.dump();
                firstCol = false;
            }
            ss << "\n";
        }
        return ss.str();
    }

    static std::string toXml(const json& j, const std::string& rootTag = "root", int indent = 0) {
        std::ostringstream ss;
        std::string pad(indent * 2, ' ');

        if (j.is_object()) {
            ss << pad << "<" << rootTag << ">\n";
            for (auto& [key, val] : j.items())
                ss << toXml(val, key, indent + 1);
            ss << pad << "</" << rootTag << ">\n";
        } else if (j.is_array()) {
            for (auto& item : j)
                ss << toXml(item, rootTag, indent);
        } else {
            std::string val = j.is_string() ? j.get<std::string>() : j.dump();
            ss << pad << "<" << rootTag << ">" << xmlEscape(val) << "</" << rootTag << ">\n";
        }
        return ss.str();
    }

    static std::string toYaml(const json& j, int indent = 0) {
        std::ostringstream ss;
        std::string pad(indent * 2, ' ');

        if (j.is_object()) {
            for (auto& [key, val] : j.items()) {
                if (val.is_object() || val.is_array()) {
                    ss << pad << key << ":\n" << toYaml(val, indent + 1);
                } else if (val.is_string()) {
                    ss << pad << key << ": " << val.get<std::string>() << "\n";
                } else {
                    ss << pad << key << ": " << val.dump() << "\n";
                }
            }
        } else if (j.is_array()) {
            for (auto& item : j) {
                if (item.is_object() || item.is_array()) {
                    ss << pad << "-\n" << toYaml(item, indent + 1);
                } else if (item.is_string()) {
                    ss << pad << "- " << item.get<std::string>() << "\n";
                } else {
                    ss << pad << "- " << item.dump() << "\n";
                }
            }
        } else {
            ss << pad << (j.is_string() ? j.get<std::string>() : j.dump()) << "\n";
        }
        return ss.str();
    }

    static std::string toToml(const json& j) {
        std::ostringstream ss;

        if (!j.is_object())
            throw std::runtime_error("TOML output requires a top-level object");

        // First pass: flat keys
        for (auto& [key, val] : j.items()) {
            if (val.is_object() || val.is_array()) continue;
            if (val.is_string())
                ss << key << " = \"" << val.get<std::string>() << "\"\n";
            else
                ss << key << " = " << val.dump() << "\n";
        }

        // Second pass: table sections
        for (auto& [key, val] : j.items()) {
            if (!val.is_object()) continue;
            ss << "\n[" << key << "]\n";
            for (auto& [k, v] : val.items()) {
                if (v.is_string())
                    ss << k << " = \"" << v.get<std::string>() << "\"\n";
                else
                    ss << k << " = " << v.dump() << "\n";
            }
        }
        return ss.str();
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    static std::vector<std::string> splitCsvLine(const std::string& line, char delim) {
        std::vector<std::string> fields;
        std::string field;
        bool inQuotes = false;

        for (size_t i = 0; i < line.size(); i++) {
            char c = line[i];
            if (c == '"') {
                if (inQuotes && i + 1 < line.size() && line[i+1] == '"') {
                    field += '"'; i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (c == delim && !inQuotes) {
                fields.push_back(field);
                field.clear();
            } else {
                field += c;
            }
        }
        fields.push_back(field);
        return fields;
    }

    static std::string escapeCsvField(const std::string& s, char delim) {
        bool needsQuotes = s.find(delim) != std::string::npos ||
                           s.find('"')  != std::string::npos ||
                           s.find('\n') != std::string::npos;
        if (!needsQuotes) return s;
        std::string out = "\"";
        for (char c : s) { if (c == '"') out += '"'; out += c; }
        return out + "\"";
    }

    static std::string xmlEscape(const std::string& s) {
        std::string out;
        for (char c : s) {
            switch (c) {
                case '&':  out += "&amp;";  break;
                case '<':  out += "&lt;";   break;
                case '>':  out += "&gt;";   break;
                case '"':  out += "&quot;"; break;
                case '\'': out += "&apos;"; break;
                default:   out += c;
            }
        }
        return out;
    }

    static json coerceValue(const std::string& s) {
        if (s == "true"  || s == "yes") return true;
        if (s == "false" || s == "no")  return false;
        if (s == "null"  || s == "~")   return nullptr;
        try { return std::stoi(s); } catch (...) {}
        try { return std::stod(s); } catch (...) {}
        return s;
    }

    static std::string trim(const std::string& s) {
        size_t start = s.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) return "";
        size_t end = s.find_last_not_of(" \t\r\n");
        return s.substr(start, end - start + 1);
    }

    static void skipWhitespace(const std::string& s, size_t& pos) {
        while (pos < s.size() && std::isspace(s[pos])) pos++;
    }

    // Recursive XML element parser
    static void parseXmlElement(const std::string& s, size_t& pos, json& out) {
        skipWhitespace(s, pos);
        if (pos >= s.size() || s[pos] != '<') return;

        pos++; // skip '<'
        std::string tag;
        while (pos < s.size() && s[pos] != '>' && s[pos] != ' ') tag += s[pos++];

        // Skip attributes for now
        while (pos < s.size() && s[pos] != '>') pos++;
        if (pos < s.size()) pos++; // skip '>'

        skipWhitespace(s, pos);

        // Check if next is a child element or text
        if (pos < s.size() && s[pos] == '<' && pos + 1 < s.size() && s[pos+1] != '/') {
            // Has child elements
            json children = json::object();
            while (pos < s.size()) {
                skipWhitespace(s, pos);
                if (pos >= s.size() || s[pos] != '<') break;
                if (s[pos+1] == '/') break; // closing tag
                json child;
                size_t tagStart = pos + 1;
                size_t tagEnd   = s.find('>', tagStart);
                std::string childTag = s.substr(tagStart, tagEnd - tagStart);
                // Strip attributes from tag name
                auto spacePos = childTag.find(' ');
                if (spacePos != std::string::npos) childTag = childTag.substr(0, spacePos);
                parseXmlElement(s, pos, child);
                if (children.contains(childTag)) {
                    if (!children[childTag].is_array()) {
                        json arr = json::array();
                        arr.push_back(children[childTag]);
                        children[childTag] = arr;
                    }
                    children[childTag].push_back(child[childTag]);
                } else {
                    children.merge_patch(child);
                }
            }
            out[tag] = children;
        } else {
            // Text content
            std::string text;
            while (pos < s.size() && s[pos] != '<') text += s[pos++];
            out[tag] = coerceValue(trim(text));
        }

        // Skip closing tag
        if (pos < s.size() && s[pos] == '<') {
            while (pos < s.size() && s[pos] != '>') pos++;
            if (pos < s.size()) pos++;
        }
    }
};

} // namespace converter