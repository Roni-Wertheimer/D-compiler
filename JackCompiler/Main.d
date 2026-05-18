import std.stdio;
import std.file;
import std.path;
import std.string;
import std.ascii;
import std.algorithm;
import std.conv;

string[] keywords = ["class", "constructor", "function", "method", "field", "static", "var", "int", "char", "boolean", "void", "true", "false", "null", "this", "let", "do", "if", "else", "while", "return"];
string symbols = "{}()[].,;+-*/&|<>=~";
string opSymbols = "+-*/&|<>=~"; // אופרטורים שיכולים לחבר בין איברים

void main() {
    write("Please enter the directory path: ");
    string dirPath = readln().strip();

    if (!exists(dirPath) || !isDir(dirPath)) {
        writeln("Error: Directory not found.");
        return;
    }

    foreach (string entry; dirEntries(dirPath, "*.jack", SpanMode.shallow)) {
        writeln("Compiling ", baseName(entry), "...");
        
        // 1. Tokenizing
        string tPath = entry[0 .. $-5] ~ "T_my.xml";
        tokenizeFile(entry, tPath);
        
        // 2. Parsing (Compilation Engine)
        string xmlPath = entry[0 .. $-5] ~ "_my.xml";
        auto engine = new CompilationEngine(tPath, xmlPath);
        engine.compileClass();
    }
    
    writeln("Project 10 compiled successfully!");
}

// ---------------------------------------------------------
// חלק א': Tokenizer
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
// חלק ב': Compilation Engine
// ---------------------------------------------------------
class CompilationEngine {
    string[] tokens;
    int pos = 0;
    File outFile;
    string indentStr = "";

    this(string tPath, string outPath) {
        outFile = File(outPath, "w");
        string[] lines = readText(tPath).splitLines();
        foreach(line; lines) {
            string t = line.strip();
            if (t != "" && t != "<tokens>" && t != "</tokens>") {
                tokens ~= t;
            }
        }
    }

    void indent() { indentStr ~= "  "; }
    void unindent() { indentStr = indentStr[0 .. $-2]; }

    string currentVal() {
        if (pos >= tokens.length) return "";
        string t = tokens[pos];
        auto start = t.indexOf('>') + 2;
        auto end = t.lastIndexOf('<') - 1;
        if (start < t.length && end >= start) return t[start .. end];
        return "";
    }

    // פונקציית lookahead - מציצה לערך של הטוקן הבא בתור מבלי לקדם את המצביע
    string nextVal() {
        if (pos + 1 >= tokens.length) return "";
        string t = tokens[pos + 1];
        auto start = t.indexOf('>') + 2;
        auto end = t.lastIndexOf('<') - 1;
        if (start < t.length && end >= start) return t[start .. end];
        return "";
    }

    void writeToken() {
        if (pos < tokens.length) {
            outFile.writeln(indentStr ~ tokens[pos]);
            pos++;
        }
    }

    void compileClass() {
        outFile.writeln(indentStr ~ "<class>");
        indent();
        writeToken(); // class
        writeToken(); // className
        writeToken(); // {
        while (currentVal() == "static" || currentVal() == "field") { compileClassVarDec(); }
        while (currentVal() == "constructor" || currentVal() == "function" || currentVal() == "method") { compileSubroutine(); }
        writeToken(); // }
        unindent();
        outFile.writeln(indentStr ~ "</class>");
    }

    void compileClassVarDec() {
        outFile.writeln(indentStr ~ "<classVarDec>");
        indent();
        writeToken(); // static | field
        writeToken(); // type
        writeToken(); // varName
        while (currentVal() == ",") { writeToken(); writeToken(); }
        writeToken(); // ;
        unindent();
        outFile.writeln(indentStr ~ "</classVarDec>");
    }

    void compileSubroutine() {
        outFile.writeln(indentStr ~ "<subroutineDec>");
        indent();
        writeToken(); // constructor | function | method
        writeToken(); // void | type
        writeToken(); // subroutineName
        writeToken(); // (
        compileParameterList();
        writeToken(); // )
        compileSubroutineBody();
        unindent();
        outFile.writeln(indentStr ~ "</subroutineDec>");
    }

    void compileParameterList() {
        outFile.writeln(indentStr ~ "<parameterList>");
        indent();
        if (currentVal() != ")") {
            writeToken(); writeToken();
            while (currentVal() == ",") { writeToken(); writeToken(); writeToken(); }
        }
        unindent();
        outFile.writeln(indentStr ~ "</parameterList>");
    }

    void compileSubroutineBody() {
        outFile.writeln(indentStr ~ "<subroutineBody>");
        indent();
        writeToken(); // {
        while (currentVal() == "var") { compileVarDec(); }
        compileStatements();
        writeToken(); // }
        unindent();
        outFile.writeln(indentStr ~ "</subroutineBody>");
    }

    void compileVarDec() {
        outFile.writeln(indentStr ~ "<varDec>");
        indent();
        writeToken(); // var
        writeToken(); // type
        writeToken(); // varName
        while (currentVal() == ",") { writeToken(); writeToken(); }
        writeToken(); // ;
        unindent();
        outFile.writeln(indentStr ~ "</varDec>");
    }

    void compileStatements() {
        outFile.writeln(indentStr ~ "<statements>");
        indent();
        while (currentVal() == "let" || currentVal() == "if" || currentVal() == "while" || currentVal() == "do" || currentVal() == "return") {
            if (currentVal() == "let") compileLet();
            else if (currentVal() == "if") compileIf();
            else if (currentVal() == "while") compileWhile();
            else if (currentVal() == "do") compileDo();
            else if (currentVal() == "return") compileReturn();
        }
        unindent();
        outFile.writeln(indentStr ~ "</statements>");
    }

    void compileLet() {
        outFile.writeln(indentStr ~ "<letStatement>");
        indent();
        writeToken(); // let
        writeToken(); // varName
        if (currentVal() == "[") {
            writeToken(); // [
            compileExpression();
            writeToken(); // ]
        }
        writeToken(); // =
        compileExpression();
        writeToken(); // ;
        unindent();
        outFile.writeln(indentStr ~ "</letStatement>");
    }

    void compileIf() {
        outFile.writeln(indentStr ~ "<ifStatement>");
        indent();
        writeToken(); // if
        writeToken(); // (
        compileExpression();
        writeToken(); // )
        writeToken(); // {
        compileStatements();
        writeToken(); // }
        if (currentVal() == "else") {
            writeToken(); // else
            writeToken(); // {
            compileStatements();
            writeToken(); // }
        }
        unindent();
        outFile.writeln(indentStr ~ "</ifStatement>");
    }

    void compileWhile() {
        outFile.writeln(indentStr ~ "<whileStatement>");
        indent();
        writeToken(); // while
        writeToken(); // (
        compileExpression();
        writeToken(); // )
        writeToken(); // {
        compileStatements();
        writeToken(); // }
        unindent();
        outFile.writeln(indentStr ~ "</whileStatement>");
    }

    void compileDo() {
        outFile.writeln(indentStr ~ "<doStatement>");
        indent();
        writeToken(); // do
        writeToken(); // identifier / className / varName
        if (currentVal() == ".") {
            writeToken(); // .
            writeToken(); // subroutineName
        }
        writeToken(); // (
        compileExpressionList();
        writeToken(); // )
        writeToken(); // ;
        unindent();
        outFile.writeln(indentStr ~ "</doStatement>");
    }

    void compileReturn() {
        outFile.writeln(indentStr ~ "<returnStatement>");
        indent();
        writeToken(); // return
        if (currentVal() != ";") { compileExpression(); }
        writeToken(); // ;
        unindent();
        outFile.writeln(indentStr ~ "</returnStatement>");
    }

    // --- שדרוג: טיפול מלא בביטויים מורכבים (פרויקט 10 המלא) ---
    void compileExpression() {
        outFile.writeln(indentStr ~ "<expression>");
        indent();
        
        compileTerm(); // איבר ראשון
        
        // כל עוד יש אופרטור (כמו +, -, *, /) אחרי האיבר, מדובר בביטוי ארוך
        while (opSymbols.canFind(currentVal())) {
            writeToken();  // כותב את האופרטור
            compileTerm(); // מנתח את האיבר הבא שבא אחריו
        }
        
        unindent();
        outFile.writeln(indentStr ~ "</expression>");
    }

    void compileTerm() {
        outFile.writeln(indentStr ~ "<term>");
        indent();
        
        // מקרה 1: אופרטורים אונאריים (כמו -5 או ~true)
        if (currentVal() == "-" || currentVal() == "~") {
            writeToken();  // כותב את ה- מינוס או ה- נוט
            compileTerm(); // מנתח רקורסיבית את ה-term שבא אחריו
        }
        // מקרה 2: ביטוי שלם בתוך סוגריים ( expression )
        else if (currentVal() == "(") {
            writeToken(); // (
            compileExpression();
            writeToken(); // )
        }
        // מקרה 3: מזהה (משתנה, מערך או קריאה לפונקציה) - דורש שימוש ב-Lookahead
        else if (tokens[pos].canFind("<identifier>")) {
            if (nextVal() == "[") { // גישה למערך: varName[expression]
                writeToken(); // varName
                writeToken(); // [
                compileExpression();
                writeToken(); // ]
            }
            else if (nextVal() == "(") { // קריאה לפונקציה ישירה: funcName(exprList)
                writeToken(); // funcName
                writeToken(); // (
                compileExpressionList();
                writeToken(); // )
            }
            else if (nextVal() == ".") { // קריאה למתודה מאובייקט: obj.method(exprList)
                writeToken(); // objName / className
                writeToken(); // .
                writeToken(); // methodName
                writeToken(); // (
                compileExpressionList();
                writeToken(); // )
            }
            else {
                // משתנה רגיל בודד
                writeToken();
            }
        }
        // מקרה 4: קבועים רגילים (מספרים, מחרוזות, מילים שמורות כמו null, true, false, this)
        else {
            writeToken();
        }
        
        unindent();
        outFile.writeln(indentStr ~ "</term>");
    }

    void compileExpressionList() {
        outFile.writeln(indentStr ~ "<expressionList>");
        indent();
        if (currentVal() != ")") {
            compileExpression();
            while (currentVal() == ",") {
                writeToken(); // ,
                compileExpression();
            }
        }
        unindent();
        outFile.writeln(indentStr ~ "</expressionList>");
    }
}