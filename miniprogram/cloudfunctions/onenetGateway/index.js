const cloud = require('wx-server-sdk')
cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

const { callOneNET } = require('./onenetApi')

exports.main = async (event, context) => {

  switch (event.action) {

    case "onenet":
      return await callOneNET(event)

    default:
      return { code: 400, msg: "invalid action" }
  }
}
