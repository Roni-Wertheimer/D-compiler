import std.stdio;
import std.file;
import std.path;
import std.string;
import std.ascii;
import std.algorithm;
import std.conv;

string[] keywords = ["class", "constructor", "function", "method", "field", "static", "var", "int", "char", "boolean", "void", "true", "false", "null", "this", "let", "do", "if", "else", "while", "return"];
string symbols = "{}()[].,;+-*/&|<>=~";
// הנה התיקון הקריטי! מערך שמכיל בדיוק את המחרוזות שמגיעות מה-XML
string[] opSymbols = ["+", "-", "*", "/", "&amp;", "|", "&lt;", "&gt;", "="];

void main() {
    write("Please enter the directory path: ");
    string dirPath = readln().strip();

    if (!exists(dirPath) || !isDir(dirPath)) {
        writeln("Error: Directory not found.");
        return;
    }

    foreach (string entry; dirEntries(dirPath, "*.jack", SpanMode.shallow)) {
        writeln("Compiling ", baseName(entry), " to VM...");
        
        string tPath = entry[0 .. $-5] ~ "T_temp.xml";
        tokenizeFile(entry, tPath);
        
        string vmPath = entry[0 .. $-5] ~ ".vm";
        auto engine = new CompilationEngine(tPath, vmPath);
        engine.compileClass();
        
        if (exists(tPath)) remove(tPath);
    }
    
    writeln("Project 11 VM Generation COMPLETED!");
}

// ---------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------
void tokenizeFile(string inputPath, string outPath) {
    File outFile = File(outPath, "w");
    outFile.writeln("<tokens>");
    string content = removeComments(readText(inputPath));
    int i = 0;
    while (i < content.length) {
        char c = content[i];
        if (isWhite(c)) { i++; continue; }
        if (symbols.canFind(c)) {
            outFile.writeln("<symbol> " ~ escapeXML(to!string(c)) ~ " </symbol>");
            i++; continue;
        }
        if (c == '"') {
            i++;
            string strConst = "";
            while (i < content.length && content[i] != '"') { strConst ~= content[i]; i++; }
            i++;
            outFile.writeln("<stringConstant> " ~ strConst ~ " </stringConstant>");
            continue;
        }
        if (isDigit(c)) {
            string intConst = "";
            while (i < content.length && isDigit(content[i])) { intConst ~= content[i]; i++; }
            outFile.writeln("<integerConstant> " ~ intConst ~ " </integerConstant>");
            continue;
        }
        if (isAlpha(c) || c == '_') {
            string word = "";
            while (i < content.length && (isAlphaNum(content[i]) || content[i] == '_')) { word ~= content[i]; i++; }
            if (keywords.canFind(word)) outFile.writeln("<keyword> " ~ word ~ " </keyword>");
            else outFile.writeln("<identifier> " ~ word ~ " </identifier>");
            continue;
        }
        i++;
    }
    outFile.writeln("</tokens>");
    outFile.close();
}

string escapeXML(string str) {
    if (str == "<") return "&lt;"; if (str == ">") return "&gt;";
    if (str == "\"") return "&quot;"; if (str == "&") return "&amp;";
    return str;
}

string removeComments(string text) {
    string result = ""; int i = 0;
    while (i < text.length) {
        if (i + 1 < text.length && text[i] == '/' && text[i+1] == '/') {
            while (i < text.length && text[i] != '\n') i++;
        }
        else if (i + 1 < text.length && text[i] == '/' && text[i+1] == '*') {
            i += 2;
            while (i + 1 < text.length && !(text[i] == '*' && text[i+1] == '/')) i++;
            i += 2;
        }
        else { result ~= text[i]; i++; }
    }
    return result;
}

// ---------------------------------------------------------
// Symbol Table & VM Writer
// ---------------------------------------------------------
enum Kind { STATIC, FIELD, ARG, VAR, NONE }

struct SymbolInfo { string type; Kind kind; int index; }

class SymbolTable {
    SymbolInfo[string] classTable;
    SymbolInfo[string] subTable;
    int[Kind] counts;

    this() {
        counts[Kind.STATIC] = 0; counts[Kind.FIELD] = 0;
        counts[Kind.ARG] = 0;    counts[Kind.VAR] = 0;
    }

    void startSubroutine() {
        subTable.clear();
        counts[Kind.ARG] = 0;
        counts[Kind.VAR] = 0;
    }

    void define(string name, string type, Kind kind) {
        SymbolInfo sym = SymbolInfo(type, kind, counts[kind]++);
        if (kind == Kind.STATIC || kind == Kind.FIELD) classTable[name] = sym;
        else subTable[name] = sym;
    }

    int varCount(Kind kind) { return counts[kind]; }
    Kind kindOf(string name) {
        if (name in subTable) return subTable[name].kind;
        if (name in classTable) return classTable[name].kind;
        return Kind.NONE;
    }
    string typeOf(string name) {
        if (name in subTable) return subTable[name].type;
        if (name in classTable) return classTable[name].type;
        return "";
    }
    int indexOf(string name) {
        if (name in subTable) return subTable[name].index;
        if (name in classTable) return classTable[name].index;
        return -1;
    }
}

class VMWriter {
    File outFile;
    this(string outPath) { outFile = File(outPath, "w"); }
    void writePush(string segment, int index) { outFile.writeln("push " ~ segment ~ " " ~ to!string(index)); }
    void writePop(string segment, int index) { outFile.writeln("pop " ~ segment ~ " " ~ to!string(index)); }
    void writeArithmetic(string command) { outFile.writeln(command); }
    void writeLabel(string label) { outFile.writeln("label " ~ label); }
    void writeGoto(string label) { outFile.writeln("goto " ~ label); }
    void writeIf(string label) { outFile.writeln("if-goto " ~ label); }
    void writeCall(string name, int nArgs) { outFile.writeln("call " ~ name ~ " " ~ to!string(nArgs)); }
    void writeFunction(string name, int nLocals) { outFile.writeln("function " ~ name ~ " " ~ to!string(nLocals)); }
    void writeReturn() { outFile.writeln("return"); }
    void writeString(string text) {
        writePush("constant", cast(int)text.length);
        writeCall("String.new", 1);
        foreach (char c; text) {
            writePush("constant", cast(int)c);
            writeCall("String.appendChar", 2);
        }
    }
    void close() { outFile.close(); }
}

// ---------------------------------------------------------
// Compilation Engine (שלב 3 המלא: תמיכה במערכים ואובייקטים!)
// ---------------------------------------------------------
class CompilationEngine {
    string[] tokens;
    int pos = 0;
    VMWriter vm;
    SymbolTable st;
    string className;
    int labelIndex = 0;

    this(string tPath, string outPath) {
        vm = new VMWriter(outPath);
        st = new SymbolTable();
        string[] lines = readText(tPath).splitLines();
        foreach(line; lines) {
            string t = line.strip();
            if (t != "" && t != "<tokens>" && t != "</tokens>") tokens ~= t;
        }
    }

    string currentVal() {
        if (pos >= tokens.length) return "";
        string t = tokens[pos];
        auto start = t.indexOf('>') + 2;
        auto end = t.lastIndexOf('<') - 1;
        if (start < t.length && end >= start) return t[start .. end];
        return "";
    }

    string nextVal() {
        if (pos + 1 >= tokens.length) return "";
        string t = tokens[pos + 1];
        auto start = t.indexOf('>') + 2;
        auto end = t.lastIndexOf('<') - 1;
        if (start < t.length && end >= start) return t[start .. end];
        return "";
    }

    void advance() { pos++; }

    string kindToSegment(Kind kind) {
        if (kind == Kind.STATIC) return "static";
        if (kind == Kind.FIELD) return "this";
        if (kind == Kind.VAR) return "local";
        if (kind == Kind.ARG) return "argument";
        return "";
    }

    // --- מבנה המחלקה ---
    void compileClass() {
        advance(); // class
        className = currentVal(); advance();
        advance(); // {
        while (currentVal() == "static" || currentVal() == "field") compileClassVarDec();
        while (currentVal() == "constructor" || currentVal() == "function" || currentVal() == "method") compileSubroutine();
        advance(); // }
        vm.close();
    }

    void compileClassVarDec() {
        Kind kind = (currentVal() == "static") ? Kind.STATIC : Kind.FIELD;
        advance(); // static | field
        string type = currentVal(); advance();
        string name = currentVal(); advance();
        st.define(name, type, kind);
        
        while (currentVal() == ",") {
            advance(); // ,
            name = currentVal(); advance();
            st.define(name, type, kind);
        }
        advance(); // ;
    }

    void compileSubroutine() {
        st.startSubroutine();
        string subType = currentVal(); advance(); // constructor | function | method
        string returnType = currentVal(); advance();
        string subName = currentVal(); advance();
        
        // מתודה מקבלת את this כפרמטר הראשון תמיד
        if (subType == "method") st.define("this", className, Kind.ARG);
        
        advance(); // (
        compileParameterList();
        advance(); // )
        
        advance(); // {
        while (currentVal() == "var") compileVarDec();
        
        vm.writeFunction(className ~ "." ~ subName, st.varCount(Kind.VAR));
        
        if (subType == "method") {
            vm.writePush("argument", 0);
            vm.writePop("pointer", 0);
        }
        else if (subType == "constructor") {
            int fieldCount = st.varCount(Kind.FIELD);
            vm.writePush("constant", fieldCount);
            vm.writeCall("Memory.alloc", 1);
            vm.writePop("pointer", 0); 
        }
        
        compileStatements();
        advance(); // }
    }

    void compileParameterList() {
        if (currentVal() != ")") {
            string type = currentVal(); advance();
            string name = currentVal(); advance();
            st.define(name, type, Kind.ARG);
            
            while (currentVal() == ",") {
                advance(); // ,
                type = currentVal(); advance();
                name = currentVal(); advance();
                st.define(name, type, Kind.ARG);
            }
        }
    }

    void compileVarDec() {
        advance(); // var
        string type = currentVal(); advance();
        string name = currentVal(); advance();
        st.define(name, type, Kind.VAR);
        
        while (currentVal() == ",") {
            advance(); // ,
            name = currentVal(); advance();
            st.define(name, type, Kind.VAR);
        }
        advance(); // ;
    }

    // --- פקודות ---
    void compileStatements() {
        while (currentVal() == "let" || currentVal() == "if" || currentVal() == "while" || currentVal() == "do" || currentVal() == "return") {
            if (currentVal() == "let") compileLet();
            else if (currentVal() == "if") compileIf();
            else if (currentVal() == "while") compileWhile();
            else if (currentVal() == "do") compileDo();
            else if (currentVal() == "return") compileReturn();
        }
    }

    void compileLet() {
        advance(); // let
        string varName = currentVal(); advance();
        Kind kind = st.kindOf(varName);
        int index = st.indexOf(varName);
        
        bool isArray = false;
        if (currentVal() == "[") {
            isArray = true;
            advance(); // [
            compileExpression();
            advance(); // ]
            
            vm.writePush(kindToSegment(kind), index);
            vm.writeArithmetic("add");
        }
        
        advance(); // =
        compileExpression();
        advance(); // ;
        
        if (isArray) {
            vm.writePop("temp", 0); 
            vm.writePop("pointer", 1); 
            vm.writePush("temp", 0); 
            vm.writePop("that", 0); 
        } else {
            vm.writePop(kindToSegment(kind), index);
        }
    }

    void compileIf() {
        string labelTrue = "IF_TRUE" ~ to!string(labelIndex);
        string labelFalse = "IF_FALSE" ~ to!string(labelIndex);
        string labelEnd = "IF_END" ~ to!string(labelIndex);
        labelIndex++;

        advance(); // if
        advance(); // (
        compileExpression();
        advance(); // )
        
        vm.writeIf(labelTrue);
        vm.writeGoto(labelFalse);
        vm.writeLabel(labelTrue);
        
        advance(); // {
        compileStatements();
        advance(); // }
        
        if (currentVal() == "else") {
            vm.writeGoto(labelEnd);
            vm.writeLabel(labelFalse);
            advance(); // else
            advance(); // {
            compileStatements();
            advance(); // }
            vm.writeLabel(labelEnd);
        } else {
            vm.writeLabel(labelFalse);
        }
    }

    void compileWhile() {
        string labelExp = "WHILE_EXP" ~ to!string(labelIndex);
        string labelEnd = "WHILE_END" ~ to!string(labelIndex);
        labelIndex++;

        vm.writeLabel(labelExp);
        advance(); // while
        advance(); // (
        compileExpression();
        advance(); // )
        
        vm.writeArithmetic("not"); 
        vm.writeIf(labelEnd); 
        
        advance(); // {
        compileStatements();
        advance(); // }
        vm.writeGoto(labelExp); 
        vm.writeLabel(labelEnd);
    }

    void compileDo() {
        advance(); // do
        compileTermCall(); 
        vm.writePop("temp", 0);
        advance(); // ;
    }

    void compileReturn() {
        advance(); // return
        if (currentVal() != ";") {
            compileExpression();
        } else {
            vm.writePush("constant", 0);
        }
        advance(); // ;
        vm.writeReturn();
    }

    // --- ביטויים ---
    void compileExpression() {
        compileTerm();
        while (opSymbols.canFind(currentVal())) {
            string op = currentVal(); advance();
            compileTerm();
            
            if (op == "+") vm.writeArithmetic("add");
            else if (op == "-") vm.writeArithmetic("sub");
            else if (op == "*") vm.writeCall("Math.multiply", 2);
            else if (op == "/") vm.writeCall("Math.divide", 2);
            else if (op == "&amp;") vm.writeArithmetic("and");
            else if (op == "|") vm.writeArithmetic("or");
            else if (op == "&lt;") vm.writeArithmetic("lt");
            else if (op == "&gt;") vm.writeArithmetic("gt");
            else if (op == "=") vm.writeArithmetic("eq");
        }
    }

    void compileTerm() {
        string val = currentVal();
        
        if (tokens[pos].canFind("<integerConstant>")) {
            vm.writePush("constant", to!int(val));
            advance();
        }
        else if (tokens[pos].canFind("<stringConstant>")) {
            vm.writeString(val);
            advance();
        }
        else if (val == "true") {
            vm.writePush("constant", 0);
            vm.writeArithmetic("not"); 
            advance();
        }
        else if (val == "false" || val == "null") {
            vm.writePush("constant", 0);
            advance();
        }
        else if (val == "this") {
            vm.writePush("pointer", 0);
            advance();
        }
        else if (val == "-" || val == "~") {
            advance(); // - או ~
            compileTerm();
            if (val == "-") vm.writeArithmetic("neg");
            if (val == "~") vm.writeArithmetic("not");
        }
        else if (val == "(") {
            advance(); // (
            compileExpression();
            advance(); // )
        }
        else if (tokens[pos].canFind("<identifier>")) {
            if (nextVal() == "[" || nextVal() == "(" || nextVal() == ".") {
                compileTermCall();
            } else {
                Kind kind = st.kindOf(val);
                int index = st.indexOf(val);
                vm.writePush(kindToSegment(kind), index);
                advance();
            }
        }
    }

    void compileTermCall() {
        string identifier = currentVal(); advance();
        
        if (currentVal() == "[") {
            Kind kind = st.kindOf(identifier);
            int index = st.indexOf(identifier);
            advance(); // [
            compileExpression();
            advance(); // ]
            vm.writePush(kindToSegment(kind), index);
            vm.writeArithmetic("add");
            vm.writePop("pointer", 1); 
            vm.writePush("that", 0); 
        }
        else if (currentVal() == "(") {
            advance(); // (
            vm.writePush("pointer", 0); 
            int nArgs = compileExpressionList();
            advance(); // )
            vm.writeCall(className ~ "." ~ identifier, nArgs + 1);
        }
        else if (currentVal() == ".") {
            advance(); // .
            string methodOrFunction = currentVal(); advance();
            advance(); // (
            
            Kind kind = st.kindOf(identifier);
            if (kind != Kind.NONE) {
                vm.writePush(kindToSegment(kind), st.indexOf(identifier)); 
                int nArgs = compileExpressionList();
                vm.writeCall(st.typeOf(identifier) ~ "." ~ methodOrFunction, nArgs + 1);
            } else {
                int nArgs = compileExpressionList();
                vm.writeCall(identifier ~ "." ~ methodOrFunction, nArgs);
            }
            advance(); // )
        }
    }

    int compileExpressionList() {
        int count = 0;
        if (currentVal() != ")") {
            compileExpression();
            count++;
            while (currentVal() == ",") {
                advance(); // ,
                compileExpression();
                count++;
            }
        }
        return count;
    }
}