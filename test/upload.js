$(function ($) {

    function generateUrl() {
        var uploadUrl = $("#uploadUrl").val();
        var uploadSize = $("#uploadSize").val();
        var uploadSizeUnit = $("#uploadSizeUnit").val();
        var randomName = $("#randomName").val();
        var size = uploadSize == "*" ? "*" : uploadSize + uploadSizeUnit;
        var allowSuffix = $("#allowSuffix").val();
        var storePath = $("#storePath").val();
        var url = uploadUrl + "?" + "size=" + size + "&suffix=" + allowSuffix + "&storePath=" + storePath + "&randomName=" + randomName;
        return url;
    }

    $("#submitForm").click(function () {

        var url = generateUrl();
        console.log(url);
        $("#uploadForm").attr("action", url);
        $("#uploadForm").submit();

    });

    $("#viewUrl").click(function() {
        var url = generateUrl();
        console.log(url);
        $(".urlPanel").text(url);
    })
});
