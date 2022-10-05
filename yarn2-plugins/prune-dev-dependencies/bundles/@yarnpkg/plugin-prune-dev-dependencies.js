/* eslint-disable */
//prettier-ignore
module.exports = {
name: "@yarnpkg/plugin-prune-dev-dependencies",
factory: function (require) {
"use strict";var plugin=(()=>{var c=Object.defineProperty;var f=Object.getOwnPropertyDescriptor;var m=Object.getOwnPropertyNames;var h=Object.prototype.hasOwnProperty;var l=(e=>typeof require<"u"?require:typeof Proxy<"u"?new Proxy(e,{get:(t,o)=>(typeof require<"u"?require:t)[o]}):e)(function(e){if(typeof require<"u")return require.apply(this,arguments);throw new Error('Dynamic require of "'+e+'" is not supported')});var w=(e,t)=>{for(var o in t)c(e,o,{get:t[o],enumerable:!0})},x=(e,t,o,n)=>{if(t&&typeof t=="object"||typeof t=="function")for(let s of m(t))!h.call(e,s)&&s!==o&&c(e,s,{get:()=>t[s],enumerable:!(n=f(t,s))||n.enumerable});return e};var C=e=>x(c({},"__esModule",{value:!0}),e);var j={};w(j,{default:()=>P});var a=l("@yarnpkg/core");var p=(e,t,o)=>{let n=t;for(let s=e.length-1,r;s>=0;s--)r=e[s],r&&(n=r(t,o,n)||n);return n&&Object.defineProperty(t,o,n),n};var d=l("clipanion"),u=a.YarnVersion??"0.0.0",i=class extends d.Command{async execute(){let t=await a.Configuration.find(this.context.cwd,this.context.plugins),{project:o}=await a.Project.find(t,this.context.cwd),n=await a.Cache.find(t);await o.restoreInstallState({restoreResolutions:!1});for(let r of o.workspaces)r.manifest.devDependencies.clear();return(await a.StreamReport.start({configuration:t,json:!1,stdout:this.context.stdout,includeLogs:!0},async r=>{await o.install({cache:n,report:r,persistProject:!1}),await o.cacheCleanup({cache:n,report:r}),await o.persistInstallStateFile()})).exitCode()}};parseInt(u[0])>=4||u[1]!=="."?i.paths=[["heroku","prune"]]:p([d.Command.Path("heroku","prune")],i.prototype,"execute");var g={commands:[i]},P=g;return C(j);})();
return plugin;
}
};
